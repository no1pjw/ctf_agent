#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo 'usage: pwn-session-watchdog.sh CHALLENGE WORK_DIR LAUNCHER_PID IDLE_SEC WALL_SEC HEARTBEAT_SEC' >&2
  exit 64
fi

challenge=$1
work_dir=$2
launcher_pid=$3
idle_seconds=$4
wall_seconds=$5
heartbeat_seconds=$6
poll_seconds=${CTF_PWN_WATCHDOG_POLL_SECONDS:-15}

[[ "$challenge" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || exit 65
[[ -d "$work_dir" ]] || exit 66
for value in "$launcher_pid" "$idle_seconds" "$wall_seconds" "$heartbeat_seconds"; do
  [[ "$value" =~ ^[0-9]+$ ]] || exit 65
done
[[ "$poll_seconds" =~ ^[0-9]+$ ]] && (( poll_seconds >= 1 && poll_seconds <= 30 )) || exit 65

progress_epoch() {
  find "$work_dir" -type f \
    \( -name state.json -o -name solve.py -o -name writeup.md -o -name '.solved' -o -path '*/evidence/private/*' \) \
    -printf '%T@\n' 2>/dev/null \
    | sort -nr | sed -n '1{s/\..*//;p;}'
}

current_stage() {
  python3 - "$work_dir/state.json" <<'PY' 2>/dev/null || printf 'setup'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    print(json.loads(path.read_text(encoding="utf-8")).get("current_stage", "setup"))
except Exception:
    print("setup")
PY
}

started=$(date +%s)
last_observed=$(progress_epoch)
[[ "$last_observed" =~ ^[0-9]+$ ]] || last_observed=0
last_progress=$started
last_report=$started
idle_warned=false
wall_warned=false

while kill -0 "$launcher_pid" 2>/dev/null; do
  sleep "$poll_seconds"
  now=$(date +%s)
  observed=$(progress_epoch)
  if [[ "$observed" =~ ^[0-9]+$ ]] && (( observed > last_observed )); then
    last_observed=$observed
    last_progress=$now
    idle_warned=false
  fi
  idle_for=$((now - last_progress))
  elapsed=$((now - started))
  stage=$(current_stage)

  if (( now - last_report >= heartbeat_seconds )); then
    printf '\n[ctf-pwn] stage=%s idle=%ss elapsed=%ss\n' "$stage" "$idle_for" "$elapsed" >&2
    last_report=$now
  fi

  if (( idle_for >= idle_seconds )) && [[ "$idle_warned" == false ]]; then
    printf '\n[ctf-pwn] 상태 경고: 추적 파일 변경이 %s초 동안 없습니다. 풀이 프로세스는 종료하지 않습니다. stage=%s\n' \
      "$idle_for" "$stage" >&2
    idle_warned=true
  fi
  if (( elapsed >= wall_seconds )) && [[ "$wall_warned" == false ]]; then
    printf '\n[ctf-pwn] 상태 경고: 실행 시간이 %s초를 넘었습니다. 풀이 프로세스는 종료하지 않습니다. stage=%s\n' \
      "$elapsed" "$stage" >&2
    wall_warned=true
  fi
done
