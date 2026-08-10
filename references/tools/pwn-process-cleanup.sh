#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo 'usage: pwn-process-cleanup.sh RUN_ID' >&2
  exit 64
fi
run_id=$1
[[ "$run_id" =~ ^ctf-[A-Za-z0-9._-]+-[0-9]{8}T[0-9]{6}Z-[0-9]+$ ]] || {
  echo 'invalid run id' >&2
  exit 65
}

declare -A excluded=()
pid=$$
while [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 1 )); do
  excluded[$pid]=1
  pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)
done

targets=()
for env_file in /proc/[0-9]*/environ; do
  pid=${env_file#/proc/}
  pid=${pid%/environ}
  [[ -z ${excluded[$pid]+x} ]] || continue
  if { tr '\0' '\n' < "$env_file"; } 2>/dev/null | grep -Fxq "CTF_PWN_RUN_ID=$run_id"; then
    targets+=("$pid")
  fi
done

if (( ${#targets[@]} == 0 )); then
  echo '정리할 실행 하위 프로세스: 없음'
  exit 0
fi

kill -TERM "${targets[@]}" 2>/dev/null || true
for _ in {1..10}; do
  remaining=()
  for pid in "${targets[@]}"; do kill -0 "$pid" 2>/dev/null && remaining+=("$pid"); done
  (( ${#remaining[@]} > 0 )) || break
  sleep 0.2
done
if (( ${#remaining[@]} > 0 )); then
  kill -KILL "${remaining[@]}" 2>/dev/null || true
fi
printf '정리한 실행 하위 프로세스: %d개\n' "${#targets[@]}"
