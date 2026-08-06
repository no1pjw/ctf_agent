#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
target_dir="${1:-$HOME/workspace/CTF/ctf-agent}"

if [[ "$source_dir" != "$target_dir" ]]; then
  if [[ -e "$target_dir" || -L "$target_dir" ]]; then
    printf 'Refusing to overwrite existing target: %s\n' "$target_dir" >&2
    exit 73
  fi
  mkdir -p "$(dirname -- "$target_dir")"
  cp -a -- "$source_dir" "$target_dir"
fi

ln -sfn shimes/AGENTS.md "$target_dir/AGENTS.md"
ln -sfn shimes/CLAUDE.md "$target_dir/CLAUDE.md"

mkdir -p "$target_dir/.claude/agents"
for agent_file in "$target_dir"/.agents/*.md; do
  agent_name="$(basename -- "$agent_file")"
  ln -sfn "../../.agents/$agent_name" "$target_dir/.claude/agents/$agent_name"
done

chmod +x \
  "$target_dir/install-wsl.sh" \
  "$target_dir/references/tools/ctf-pwn-start.sh" \
  "$target_dir/references/tools/ctf-learn.sh" \
  "$target_dir/references/tools/ctf-export.sh" \
  "$target_dir/references/tools/pwn-env-preflight.sh" \
  "$target_dir/references/tools/pwn-build.sh" \
  "$target_dir/references/tools/pwn-run.sh" \
  "$target_dir/references/tools/pwn-triage.sh" \
  "$target_dir/references/tools/sandbox-run.sh" \
  "$target_dir/references/tools/pwntools-template.py"

mkdir -p "$HOME/.local/bin"
ln -sfn "$target_dir/references/tools/ctf-pwn-start.sh" "$HOME/.local/bin/ctf-pwn"
ln -sfn "$target_dir/references/tools/ctf-learn.sh" "$HOME/.local/bin/ctf-learn"
ln -sfn "$target_dir/references/tools/ctf-export.sh" "$HOME/.local/bin/ctf-export"

mkdir -p "$HOME/.codex/skills"
for spec in ctf-rev:rev-agent/skills ctf-pwn:pwn-agent/skills ctf-web:web-agent/skills ctf-learn:learn-agent/skills/ctf-learn; do
  skill_name="${spec%%:*}"
  skill_rel="${spec#*:}"
  link_path="$HOME/.codex/skills/$skill_name"
  skill_source="$target_dir/$skill_rel"

  if [[ ! -e "$link_path" && ! -L "$link_path" ]]; then
    ln -s "$skill_source" "$link_path"
  elif [[ "$(readlink -f -- "$link_path" 2>/dev/null || true)" != "$(readlink -f -- "$skill_source")" ]]; then
    printf 'Skill link conflict; kept existing path: %s\n' "$link_path" >&2
  fi
done

printf 'Installed CTF agent: %s\n' "$target_dir"
printf 'Pwn launcher:        %s\n' "$HOME/.local/bin/ctf-pwn"
printf 'Learning command:    %s\n' "$HOME/.local/bin/ctf-learn"
printf 'Export command:      %s\n' "$HOME/.local/bin/ctf-export"
printf 'Start with: cd %q && codex\n' "$target_dir"
