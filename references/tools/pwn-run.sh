#!/usr/bin/env bash
set -euo pipefail

entrypoint=
timeout_seconds=15
kill_after_seconds=${CTF_PWN_KILL_AFTER_SECONDS:-2}
output_file=
runtime_dir=
structural_runtime_dir=
binary_path=
service_mode=false
docker_bin=${CTF_DOCKER_BIN:-docker}
runtime_entrypoint=/ctf-runtime/ld.so
runtime_library_dir=/ctf-runtime

show_usage() {
  cat <<'EOF'
usage: pwn-run.sh [--entrypoint PATH] [--timeout SEC] [--output FILE] IMAGE COMMAND [ARG ...]
       pwn-run.sh --service [--entrypoint PATH] [--timeout SEC] [--output FILE] IMAGE [ARG ...]
       pwn-run.sh --runtime-dir DIR --binary FILE [--timeout SEC] [--output FILE] IMAGE [ARG ...]
       pwn-run.sh --structural-runtime-dir DIR --binary FILE [--timeout SEC] [--output FILE] IMAGE [ARG ...]

Bare IMAGE execution is rejected because an image CMD may be a long-running
service. Use --service only from a solver that actively drives that service.
The runtime form mounts a verified libc/loader bundle and invokes the target
through /ctf-runtime/ld.so --library-path /ctf-runtime inside the sandbox.
The structural form uses the exact image libc/loader recorded in an incompatible
runtime manifest. It validates local control flow only, never remote offsets.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --entrypoint) entrypoint=${2:-}; shift 2 ;;
    --timeout) timeout_seconds=${2:-}; shift 2 ;;
    --service) service_mode=true; shift ;;
    --output) output_file=${2:-}; shift 2 ;;
    --runtime-dir) runtime_dir=${2:-}; shift 2 ;;
    --structural-runtime-dir) structural_runtime_dir=${2:-}; shift 2 ;;
    --binary) binary_path=${2:-}; shift 2 ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    --) shift; break ;;
    --*) echo "unknown option: $1" >&2; exit 64 ;;
    *) break ;;
  esac
done

if [[ $# -lt 1 ]]; then
  show_usage >&2
  exit 64
fi

[[ "$timeout_seconds" =~ ^[0-9]+$ ]] && (( timeout_seconds >= 1 && timeout_seconds <= 900 )) || {
  echo '--timeout must be 1..900 seconds' >&2
  exit 65
}
[[ "$kill_after_seconds" =~ ^[0-9]+$ ]] && (( kill_after_seconds >= 1 && kill_after_seconds <= 30 )) || {
  echo 'CTF_PWN_KILL_AFTER_SECONDS must be 1..30 seconds' >&2
  exit 65
}

if [[ -n "$runtime_dir" || -n "$structural_runtime_dir" || -n "$binary_path" ]]; then
  [[ -n "$binary_path" ]] || {
    echo '--runtime-dir/--structural-runtime-dir requires --binary' >&2
    exit 64
  }
  [[ -z "$runtime_dir" || -z "$structural_runtime_dir" ]] || {
    echo '--runtime-dir and --structural-runtime-dir are mutually exclusive' >&2
    exit 64
  }
  [[ -n "$runtime_dir" || -n "$structural_runtime_dir" ]] || {
    echo '--binary requires --runtime-dir or --structural-runtime-dir' >&2
    exit 64
  }
  [[ -z "$entrypoint" ]] || {
    echo '--entrypoint cannot be combined with --runtime-dir' >&2
    exit 64
  }
  [[ -f "$binary_path" ]] || { printf 'target binary not found: %s\n' "$binary_path" >&2; exit 66; }
  binary_path=$(readlink -e -- "$binary_path")
  if [[ -n "$runtime_dir" ]]; then
    [[ -d "$runtime_dir" ]] || { printf 'runtime directory not found: %s\n' "$runtime_dir" >&2; exit 66; }
    [[ -f "$runtime_dir/runtime.env" ]] || { echo 'runtime.env is missing' >&2; exit 66; }
    [[ -f "$runtime_dir/libc.so.6" && -f "$runtime_dir/ld.so" ]] || {
      echo 'verified canonical libc/loader pair is incomplete' >&2
      exit 66
    }
    runtime_status=$(sed -n 's/^runtime_status=//p' "$runtime_dir/runtime.env" | sed -n '1p')
    [[ "$runtime_status" == ready ]] || {
      printf 'runtime bundle is not ready: %s\n' "${runtime_status:-unknown}" >&2
      exit 65
    }
    runtime_dir=$(readlink -e -- "$runtime_dir")
  else
    [[ -d "$structural_runtime_dir" ]] || { printf 'runtime directory not found: %s\n' "$structural_runtime_dir" >&2; exit 66; }
    structural_runtime_dir=$(readlink -e -- "$structural_runtime_dir")
    manifest="$structural_runtime_dir/runtime.env"
    [[ -f "$manifest" ]] || { echo 'runtime.env is missing' >&2; exit 66; }
    manifest_value() {
      bash -c 'set -eu; source "$1"; printf "%s" "${!2-}"' bash "$manifest" "$1"
    }
    structural_libc=$(readlink -e -- "$(manifest_value local_libc_path)" 2>/dev/null || true)
    structural_ld=$(readlink -e -- "$(manifest_value local_ld_path)" 2>/dev/null || true)
    [[ -f "$structural_libc" && -f "$structural_ld" ]] || {
      echo 'exact image libc/loader pair is unavailable for structural validation' >&2
      exit 66
    }
    case "$structural_libc" in "$structural_runtime_dir"/*) ;; *) echo 'local libc escaped runtime directory' >&2; exit 65 ;; esac
    case "$structural_ld" in "$structural_runtime_dir"/*) ;; *) echo 'local loader escaped runtime directory' >&2; exit 65 ;; esac
    structural_ld_rel=${structural_ld#"$structural_runtime_dir"/}
    structural_libc_rel=${structural_libc#"$structural_runtime_dir"/}
    [[ "$(dirname -- "$structural_ld_rel")" == "$(dirname -- "$structural_libc_rel")" ]] || {
      echo 'image libc and loader are not in the same runtime directory' >&2
      exit 65
    }
    runtime_entrypoint="/ctf-runtime/$structural_ld_rel"
    runtime_library_dir="/ctf-runtime/$(dirname -- "$structural_libc_rel")"
    echo 'runtime_scope=local-structure-only (remote libc offsets are not validated)' >&2
  fi
fi

image=$1
shift
timeout --kill-after="${kill_after_seconds}s" 10 \
  "$docker_bin" image inspect "$image" >/dev/null 2>&1 || {
    echo "image unavailable or Docker inspect timed out: $image" >&2
    exit 66
  }

if [[ -z "$runtime_dir" && -z "$structural_runtime_dir" && $# -eq 0 && "$service_mode" == false ]]; then
  echo 'refusing bare IMAGE execution: pass an explicit COMMAND, or use --service from an active solver' >&2
  exit 64
fi

docker_args=(
  run --rm --interactive
  --network none
  --read-only
  --cap-drop ALL
  --security-opt no-new-privileges
  --pids-limit 128
  --memory 512m
  --cpus 1
  --tmpfs /tmp:rw,noexec,nosuid,size=128m
)

run_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/ctf-pwn-run.XXXXXX")
cid_file="$run_tmp_dir/container.cid"
cleanup_owned_container() {
  local cid=
  if [[ -s "$cid_file" ]]; then
    IFS= read -r cid < "$cid_file" || true
    if [[ "$cid" =~ ^[0-9a-f]{12,64}$ ]]; then
      timeout --kill-after="${kill_after_seconds}s" 5 \
        "$docker_bin" rm --force "$cid" >/dev/null 2>&1 || true
    fi
  fi
  rm -f -- "$cid_file"
  rmdir -- "$run_tmp_dir" 2>/dev/null || true
}
trap cleanup_owned_container EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
docker_args+=(--cidfile "$cid_file")
if [[ -n "${CTF_BENCH_RUN_ID:-}" ]]; then
  [[ "$CTF_BENCH_RUN_ID" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo 'invalid CTF_BENCH_RUN_ID' >&2; exit 65; }
  docker_args+=(--label "ctf.bench.run=$CTF_BENCH_RUN_ID")
fi
if [[ -n "${CTF_BENCH_VARIANT:-}" ]]; then
  [[ "$CTF_BENCH_VARIANT" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo 'invalid CTF_BENCH_VARIANT' >&2; exit 65; }
  docker_args+=(--label "ctf.bench.variant=$CTF_BENCH_VARIANT")
fi
if [[ -n "$runtime_dir" ]]; then
  docker_args+=(
    --mount "type=bind,src=$runtime_dir,dst=/ctf-runtime,readonly"
    --mount "type=bind,src=$binary_path,dst=/ctf-target/chall,readonly"
    --entrypoint /ctf-runtime/ld.so
  )
elif [[ -n "$structural_runtime_dir" ]]; then
  docker_args+=(
    --mount "type=bind,src=$structural_runtime_dir,dst=/ctf-runtime,readonly"
    --mount "type=bind,src=$binary_path,dst=/ctf-target/chall,readonly"
    --entrypoint "$runtime_entrypoint"
  )
elif [[ -n "$entrypoint" ]]; then
  docker_args+=(--entrypoint "$entrypoint")
fi
if [[ -n "$runtime_dir" || -n "$structural_runtime_dir" ]]; then
  docker_args+=("$image" --library-path "$runtime_library_dir" /ctf-target/chall "$@")
else
  docker_args+=("$image" "$@")
fi

if [[ -n "$output_file" ]]; then
  mkdir -p "$(dirname -- "$output_file")"
  set +e
  timeout --kill-after="${kill_after_seconds}s" "$timeout_seconds" \
    "$docker_bin" "${docker_args[@]}" 2>&1 | tee "$output_file"
  status=${PIPESTATUS[0]}
  set -e
  if [[ $status -eq 124 || $status -eq 137 ]]; then
    printf 'local_run_timeout=%ss; owned container cleanup requested\n' "$timeout_seconds" >&2
  fi
  exit "$status"
fi

set +e
timeout --kill-after="${kill_after_seconds}s" "$timeout_seconds" \
  "$docker_bin" "${docker_args[@]}"
status=$?
set -e
if [[ $status -eq 124 || $status -eq 137 ]]; then
  printf 'local_run_timeout=%ss; owned container cleanup requested\n' "$timeout_seconds" >&2
fi
exit "$status"
