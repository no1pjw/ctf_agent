#!/usr/bin/env bash
set -euo pipefail

entrypoint=
timeout_seconds=15
output_file=
runtime_dir=
binary_path=
docker_bin=${CTF_DOCKER_BIN:-docker}

show_usage() {
  cat <<'EOF'
usage: pwn-run.sh [--entrypoint PATH] [--timeout SEC] [--output FILE] IMAGE [COMMAND ...]
       pwn-run.sh --runtime-dir DIR --binary FILE [--timeout SEC] [--output FILE] IMAGE [ARG ...]

The runtime form mounts a verified libc/loader bundle and invokes the target
through /ctf-runtime/ld.so --library-path /ctf-runtime inside the sandbox.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --entrypoint) entrypoint=${2:-}; shift 2 ;;
    --timeout) timeout_seconds=${2:-}; shift 2 ;;
    --output) output_file=${2:-}; shift 2 ;;
    --runtime-dir) runtime_dir=${2:-}; shift 2 ;;
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

if [[ -n "$runtime_dir" || -n "$binary_path" ]]; then
  [[ -n "$runtime_dir" && -n "$binary_path" ]] || {
    echo '--runtime-dir and --binary must be used together' >&2
    exit 64
  }
  [[ -z "$entrypoint" ]] || {
    echo '--entrypoint cannot be combined with --runtime-dir' >&2
    exit 64
  }
  [[ -d "$runtime_dir" ]] || { printf 'runtime directory not found: %s\n' "$runtime_dir" >&2; exit 66; }
  [[ -f "$binary_path" ]] || { printf 'target binary not found: %s\n' "$binary_path" >&2; exit 66; }
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
  binary_path=$(readlink -e -- "$binary_path")
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
elif [[ -n "$entrypoint" ]]; then
  docker_args+=(--entrypoint "$entrypoint")
fi
if [[ -n "$runtime_dir" ]]; then
  docker_args+=("$image" --library-path /ctf-runtime /ctf-target/chall "$@")
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
