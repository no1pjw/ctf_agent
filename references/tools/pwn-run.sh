#!/usr/bin/env bash
set -euo pipefail

entrypoint=
timeout_seconds=15
output_file=

while [[ $# -gt 0 ]]; do
  case "$1" in
    --entrypoint) entrypoint=${2:-}; shift 2 ;;
    --timeout) timeout_seconds=${2:-}; shift 2 ;;
    --output) output_file=${2:-}; shift 2 ;;
    -h|--help)
      echo "usage: $0 [--entrypoint PATH] [--timeout SEC] [--output FILE] IMAGE [COMMAND ...]"
      exit 0
      ;;
    --) shift; break ;;
    --*) echo "unknown option: $1" >&2; exit 64 ;;
    *) break ;;
  esac
done

if [[ $# -lt 1 ]]; then
  echo "usage: $0 [--entrypoint PATH] [--timeout SEC] [--output FILE] IMAGE [COMMAND ...]" >&2
  exit 64
fi

image=$1
shift
docker image inspect "$image" >/dev/null 2>&1 || { echo "image not found: $image" >&2; exit 66; }

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
if [[ -n "$entrypoint" ]]; then
  docker_args+=(--entrypoint "$entrypoint")
fi
docker_args+=("$image" "$@")

if [[ -n "$output_file" ]]; then
  mkdir -p "$(dirname -- "$output_file")"
  set +e
  timeout --foreground "$timeout_seconds" docker "${docker_args[@]}" 2>&1 | tee "$output_file"
  status=${PIPESTATUS[0]}
  set -e
  exit "$status"
fi

exec timeout --foreground "$timeout_seconds" docker "${docker_args[@]}"
