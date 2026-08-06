#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 ctf-<challenge>:local" >&2
  exit 64
fi

image=$1
if [[ ! "$image" =~ ^ctf-[a-z0-9.-]+:local$ ]]; then
  printf '안전하지 않은 이미지 이름을 거부합니다: %s\n' "$image" >&2
  exit 65
fi

if ! docker info >/dev/null 2>&1; then
  echo 'Docker daemon을 사용할 수 없어 정리를 건너뜁니다.' >&2
  exit 69
fi

mapfile -t container_ids < <(docker ps -aq --filter "ancestor=$image")
if [[ ${#container_ids[@]} -gt 0 ]]; then
  docker rm -f -- "${container_ids[@]}" >/dev/null
  printf '삭제한 문제 컨테이너: %d개\n' "${#container_ids[@]}"
else
  echo '삭제할 문제 컨테이너: 없음'
fi

if docker image inspect "$image" >/dev/null 2>&1; then
  docker image rm -f -- "$image" >/dev/null
  printf '삭제한 문제 이미지: %s\n' "$image"
else
  printf '삭제할 문제 이미지 없음: %s\n' "$image"
fi
