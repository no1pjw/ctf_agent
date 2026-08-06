#!/usr/bin/env bash
set -euo pipefail

host=
port=
timeout_seconds=30
attempts=1
output_file=

usage() {
  echo "usage: $0 --host HOST --port PORT [--timeout SEC] [--attempts 1|2] --output FILE -- COMMAND [ARG ...]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) host=${2:-}; shift 2 ;;
    --port) port=${2:-}; shift 2 ;;
    --timeout) timeout_seconds=${2:-}; shift 2 ;;
    --attempts) attempts=${2:-}; shift 2 ;;
    --output) output_file=${2:-}; shift 2 ;;
    --) shift; break ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 64 ;;
  esac
done

[[ -n "$host" && -n "$port" && -n "$output_file" && $# -gt 0 ]] || { usage >&2; exit 64; }
if [[ "$host" == *:* ]]; then
  [[ "$host" =~ ^[0-9A-Fa-f:]+$ ]] || { echo 'invalid host' >&2; exit 65; }
else
  [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]] || { echo 'invalid host' >&2; exit 65; }
fi
[[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )) || { echo 'invalid port' >&2; exit 65; }
[[ "$timeout_seconds" =~ ^[0-9]+$ ]] && (( timeout_seconds >= 1 && timeout_seconds <= 60 )) || { echo 'timeout must be 1..60' >&2; exit 65; }
[[ "$attempts" =~ ^[12]$ ]] || { echo 'attempts must be 1 or 2' >&2; exit 65; }

mkdir -p "$(dirname -- "$output_file")"
: > "$output_file"
chmod 600 "$output_file"

status=1

monotonic_ns() {
  python3 -c 'import time; print(time.monotonic_ns())'
}

stream_remote_output() {
  local start_ns=$1
  local line now_ns elapsed_ms
  local flag_printed=false

  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "$line"
    if [[ "$flag_printed" == false && "$line" =~ ^FLAG=[^[:cntrl:]]+$ ]]; then
      now_ns="$(monotonic_ns)"
      elapsed_ms=$(( (now_ns - start_ns) / 1000000 ))
      printf '\n획득한 플래그: %s\n' "${line#FLAG=}"
      printf '원격 플래그 획득 시간: %d.%03d초\n' "$((elapsed_ms / 1000))" "$((elapsed_ms % 1000))"
      flag_printed=true
    fi
  done
}

for ((attempt = 1; attempt <= attempts; attempt++)); do
  printf '=== remote attempt %d/%d: %s:%s ===\n' "$attempt" "$attempts" "$host" "$port" | tee -a "$output_file"
  start_ns="$(monotonic_ns)"
  set +e
  timeout --foreground "$timeout_seconds" env \
    CTF_REMOTE_HOST="$host" CTF_REMOTE_PORT="$port" \
    "$@" REMOTE "HOST=$host" "PORT=$port" 2>&1 \
    | stream_remote_output "$start_ns" \
    | tee -a "$output_file"
  status=${PIPESTATUS[0]}
  set -e
  printf 'exit_status=%s\n' "$status" | tee -a "$output_file"
  flag_line="$(grep -aE '^FLAG=[^[:cntrl:]]+$' "$output_file" | tail -n 1 || true)"
  if [[ -n "$flag_line" ]]; then
    status=0
    break
  fi
  if [[ $status -eq 0 ]]; then
    status=74
    printf '검증된 FLAG= 출력이 없어 원격 실행을 성공으로 처리하지 않습니다.\n' | tee -a "$output_file"
  fi
  [[ $status -ne 0 && $attempt -lt $attempts ]] || break
done

exit "$status"
