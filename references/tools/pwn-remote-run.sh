#!/usr/bin/env bash
set -euo pipefail

host=
port=
timeout_seconds=30
attempts=1
output_file=
max_log_bytes=${CTF_REMOTE_LOG_MAX_BYTES:-1048576}
local_flag_denylist=${CTF_LOCAL_FLAG_DENYLIST:-}
solved_marker=${CTF_PWN_SOLVED_MARKER:-}
placeholder_marker=${CTF_PWN_REMOTE_PLACEHOLDER_MARKER:-}

usage() {
  echo "usage: $0 --host HOST --port PORT [--timeout SEC] [--attempts N] --output FILE -- COMMAND [ARG ...]"
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
[[ "$attempts" =~ ^[1-9][0-9]*$ ]] || { echo 'attempts must be a positive integer' >&2; exit 65; }
[[ "$max_log_bytes" =~ ^[0-9]+$ ]] && (( max_log_bytes >= 65536 && max_log_bytes <= 10485760 )) || { echo 'CTF_REMOTE_LOG_MAX_BYTES must be 65536..10485760' >&2; exit 65; }

mkdir -p "$(dirname -- "$output_file")"
: > "$output_file"
chmod 600 "$output_file"

status=1

monotonic_ns() {
  python3 -c 'import time; print(time.monotonic_ns())'
}

is_local_placeholder() {
  local candidate=$1
  [[ -n "$local_flag_denylist" && -f "$local_flag_denylist" ]] || return 1
  grep -Fqx -- "$candidate" "$local_flag_denylist"
}

stream_remote_output() {
  local start_ns=$1
  local capture_file=$2
  local line now_ns elapsed_ms flag_marker
  local flag_printed=false
  local truncated=false current_size line_size
  current_size=$(stat -c %s -- "$capture_file" 2>/dev/null || printf '0')

  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "$line"
    line_size=$((${#line} + 1))
    if (( current_size + line_size <= max_log_bytes )); then
      printf '%s\n' "$line" >> "$capture_file"
      current_size=$((current_size + line_size))
    elif [[ "$truncated" == false ]]; then
      printf '[transcript truncated at %s bytes]\n' "$max_log_bytes" >> "$capture_file"
      truncated=true
    fi
    flag_marker=$(printf '%s\n' "$line" | grep -aoE 'FLAG=[A-Za-z][A-Za-z0-9_]{0,31}\{[^{}[:cntrl:]]{1,256}\}' | tail -n 1 || true)
    if [[ "$flag_printed" == false && -n "$flag_marker" ]]; then
      if is_local_placeholder "${flag_marker#FLAG=}"; then
        printf '\n원격 후보가 로컬 placeholder와 일치하여 거부했습니다: %s\n' "${flag_marker#FLAG=}"
        flag_printed=true
        continue
      fi
      if (( current_size + line_size > max_log_bytes )); then
        printf '%s\n' "$flag_marker" >> "$capture_file"
      fi
      now_ns="$(monotonic_ns)"
      elapsed_ms=$(( (now_ns - start_ns) / 1000000 ))
      printf '\n획득한 플래그: %s\n' "${flag_marker#FLAG=}"
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
    | stream_remote_output "$start_ns" "$output_file"
  status=${PIPESTATUS[0]}
  set -e
  printf 'exit_status=%s\n' "$status" | tee -a "$output_file"
  flag_line="$(grep -aoE 'FLAG=[A-Za-z][A-Za-z0-9_]{0,31}\{[^{}[:cntrl:]]{1,256}\}' "$output_file" | tail -n 1 || true)"
  if [[ -n "$flag_line" ]]; then
    if is_local_placeholder "${flag_line#FLAG=}"; then
      status=75
      if [[ -n "$placeholder_marker" ]]; then
        mkdir -p "$(dirname -- "$placeholder_marker")"
        printf '%s\n' "${flag_line#FLAG=}" > "$placeholder_marker"
      fi
      printf '로컬 placeholder와 동일한 원격 후보는 검증된 플래그로 인정하지 않습니다.\n' | tee -a "$output_file"
    else
      status=0
      [[ -z "$placeholder_marker" ]] || rm -f -- "$placeholder_marker"
      if [[ -n "$solved_marker" ]]; then
        mkdir -p "$(dirname -- "$solved_marker")"
        printf 'verified\n' > "$solved_marker"
      fi
      break
    fi
  fi
  if [[ $status -eq 0 ]]; then
    status=74
    printf '검증된 FLAG= 출력이 없어 원격 실행을 성공으로 처리하지 않습니다.\n' | tee -a "$output_file"
  fi
  [[ $status -ne 0 && $attempt -lt $attempts ]] || break
done

exit "$status"
