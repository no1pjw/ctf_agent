#!/usr/bin/env bash
set -euo pipefail

attempts=${CTF_DOCKER_READY_ATTEMPTS:-3}
timeout_seconds=${CTF_DOCKER_READY_TIMEOUT_SECONDS:-12}
docker_bin=${CTF_DOCKER_BIN:-docker}

[[ "$attempts" =~ ^[1-9][0-9]*$ && "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] || {
  echo 'invalid Docker readiness retry configuration' >&2
  exit 65
}

for ((attempt=1; attempt<=attempts; attempt++)); do
  if timeout --foreground --kill-after=2s "${timeout_seconds}s" \
    "$docker_bin" version --format '{{.Server.Version}}' >/dev/null 2>&1; then
    exit 0
  fi
  if (( attempt < attempts )); then
    printf 'Docker daemon 응답 지연: %d/%d 실패, 재시도합니다.\n' "$attempt" "$attempts" >&2
    sleep 1
  fi
done

printf 'Docker daemon이 회당 %s초, 총 %s회 검사에 응답하지 않았습니다.\n' "$timeout_seconds" "$attempts" >&2
exit 69
