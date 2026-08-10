#!/usr/bin/env bash
set -euo pipefail

if [[ ${CTF_PWN_BENCHMARK:-false} == true ]]; then
  echo 'checkpoint=skipped-benchmark'
  exit 0
fi

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo 'usage: pwn-checkpoint.sh CHALLENGE STAGE STATUS [SUMMARY]' >&2
  exit 64
fi

challenge=$1
stage=$2
status=$3
summary=${4:-}
agent_root=${CTF_AGENT_ROOT:-$HOME/workspace/CTF/ctf-agent}
challenge_dir="$agent_root/challenges/$challenge"
state_file="$challenge_dir/work/state.json"

[[ "$challenge" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo 'invalid challenge name' >&2; exit 65; }
[[ "$stage" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo 'invalid stage name' >&2; exit 65; }
case "$status" in pending|active|passed|failed|blocked) ;; *) echo 'invalid status' >&2; exit 65 ;; esac
[[ -d "$challenge_dir/work" ]] || { printf 'missing work directory: %s\n' "$challenge_dir/work" >&2; exit 66; }

STAGE="$stage" STATUS="$status" SUMMARY="$summary" STATE_FILE="$state_file" python3 - <<'PY'
import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path

path = Path(os.environ["STATE_FILE"])
try:
    state = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
except (OSError, json.JSONDecodeError):
    state = {}

summary = os.environ.get("SUMMARY", "").replace("\x00", "")[:1200]
entry = {
    "time_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    "stage": os.environ["STAGE"],
    "status": os.environ["STATUS"],
    "summary": summary,
}
history = state.get("history", [])
if not isinstance(history, list):
    history = []
history.append(entry)
history = history[-20:]
state = {
    "version": 1,
    "current_stage": entry["stage"],
    "status": entry["status"],
    "updated_utc": entry["time_utc"],
    "history": history,
}

path.parent.mkdir(parents=True, exist_ok=True)
fd, temp_name = tempfile.mkstemp(prefix=".state.", suffix=".json", dir=path.parent)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(state, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    os.replace(temp_name, path)
finally:
    try:
        os.unlink(temp_name)
    except FileNotFoundError:
        pass
PY

case "$stage:$status" in
  primitive:passed|leak:passed|arbitrary-read-write:passed|control-flow:passed)
    solver="$challenge_dir/work/solve.py"
    template="$agent_root/references/tools/pwntools-template.py"
    if [[ ! -e "$solver" && -f "$template" ]]; then
      cp -- "$template" "$solver"
      chmod 755 "$solver"
      printf 'solver scaffold: %s\n' "$solver"
    fi
    ;;
esac

printf 'checkpoint: %s %s\n' "$stage" "$status"
