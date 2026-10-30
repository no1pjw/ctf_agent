#!/usr/bin/env bash
set -euo pipefail

rebuild=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild) rebuild=true; shift ;;
    -h|--help)
      echo "usage: $0 [--rebuild] CONTEXT IMAGE"
      exit 0
      ;;
    --*) echo "unknown option: $1" >&2; exit 64 ;;
    *) break ;;
  esac
done

if [[ $# -ne 2 ]]; then
  echo "usage: $0 [--rebuild] CONTEXT IMAGE" >&2
  exit 64
fi

context=$1
image=$2
dockerfile="$context/Dockerfile"
[[ -f "$dockerfile" ]] || { echo "Dockerfile not found: $dockerfile" >&2; exit 66; }
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
docker_ready_tool="$script_dir/ctf-docker-ready.sh"

if ! "$docker_ready_tool"; then
  echo 'Docker daemon 재시도 검사에 실패해 이미지 빌드를 건너뜁니다.' >&2
  exit 69
fi

if [[ "$rebuild" == false ]] && timeout --kill-after=2s 15s docker image inspect "$image" >/dev/null 2>&1; then
  printf 'docker_image=cache-hit:%s\n' "$image"
  exit 0
fi

base_ref="$(awk 'toupper($1)=="FROM" {print $2; exit}' "$dockerfile")"
[[ -n "$base_ref" ]] || { echo 'Dockerfile has no FROM instruction' >&2; exit 67; }

printf 'build_network=enabled-for-docker-build-only\n'
printf 'base_image=%s\n' "$base_ref"
docker build --tag "$image" "$context"
