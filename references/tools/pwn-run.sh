#!/usr/bin/env bash
set -euo pipefail

entrypoint=
timeout_seconds=15
output_file=
runtime_dir=
structural_runtime_dir=
binary_path=
docker_bin=${CTF_DOCKER_BIN:-docker}
runtime_entrypoint=/ctf-runtime/ld.so
runtime_library_dir=/ctf-runtime

show_usage() {
  cat <<'EOF'
usage: pwn-run.sh [--entrypoint PATH] [--timeout SEC] [--output FILE] IMAGE [COMMAND ...]
       pwn-run.sh --runtime-dir DIR --binary FILE [--timeout SEC] [--output FILE] IMAGE [ARG ...]
       pwn-run.sh --structural-runtime-dir DIR --binary FILE [--timeout SEC] [--output FILE] IMAGE [ARG ...]

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
"$docker_bin" image inspect "$image" >/dev/null 2>&1 || { echo "image not found: $image" >&2; exit 66; }

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
  timeout --foreground "$timeout_seconds" "$docker_bin" "${docker_args[@]}" 2>&1 | tee "$output_file"
  status=${PIPESTATUS[0]}
  set -e
  exit "$status"
fi

exec timeout --foreground "$timeout_seconds" "$docker_bin" "${docker_args[@]}"
