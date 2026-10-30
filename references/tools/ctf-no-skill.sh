#!/usr/bin/env bash

# Build per-invocation Codex arguments for a clean, skill-free run. This does
# not edit the user's Codex configuration and therefore cannot affect later
# interactive sessions.
ctf_no_skill_codex_args() {
  local agent_root=${1:-}
  local codex_home=${CODEX_HOME:-$HOME/.codex}
  local skill_config
  local root path
  local -a roots=(
    "$codex_home/skills"
    "$HOME/.agents/skills"
    /etc/codex/skills
  )
  local -a skill_paths=()
  declare -A seen=()

  if [[ -n "$agent_root" ]]; then
    roots+=("$agent_root/.agents/skills")
    for path in \
      "$agent_root/pwn-agent/skills/SKILL.md" \
      "$agent_root/rev-agent/skills/SKILL.md" \
      "$agent_root/web-agent/skills/SKILL.md" \
      "$agent_root/learn-agent/skills/ctf-learn/SKILL.md" \
      "$agent_root/writeup-agent/skills/ctf-writeup/SKILL.md"; do
      if [[ -f "$path" && -z ${seen[$path]+x} ]]; then
        seen[$path]=1
        skill_paths+=("$path")
      fi
    done
  fi

  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r -d '' path; do
      [[ -z ${seen[$path]+x} ]] || continue
      seen[$path]=1
      skill_paths+=("$path")
    done < <(find -L "$root" -type f -name SKILL.md -print0 2>/dev/null)
  done

  CTF_NO_SKILL_CODEX_ARGS=(-c project_doc_max_bytes=0)
  if (( ${#skill_paths[@]} > 0 )); then
    skill_config=$(
      printf '%s\0' "${skill_paths[@]}" | python3 -c '
import json
import sys

paths = [item.decode() for item in sys.stdin.buffer.read().split(b"\0") if item]
print("[" + ",".join("{path=" + json.dumps(path) + ",enabled=false}" for path in paths) + "]")
'
    )
    CTF_NO_SKILL_CODEX_ARGS+=(-c "skills.config=$skill_config")
  fi
}
