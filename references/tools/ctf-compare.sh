#!/usr/bin/env bash
set -euo pipefail

command_name=$(basename -- "$0")
case "$command_name" in
  ctf-compare-pwn) category=pwn ;;
  ctf-compare-rev) category=rev ;;
  ctf-compare-web) category=web ;;
  *) echo 'ctf-compare-{pwn,rev,web} 이름으로 실행하세요.' >&2; exit 64 ;;
esac

usage() {
  printf '사용법: %s [--source ROOT] [기존 분야 옵션] 문제이름 [공식 endpoint]\n' "$command_name"
  printf '동일 원본을 Codex 단독과 Claude→Codex의 격리된 작업공간에서 순차 비교합니다.\n'
  printf '%s\n' '--no-skill을 지정하면 두 방식 모두 분야 스킬 없이 비교합니다.'
}

[[ $# -gt 0 ]] || { usage; exit 64; }
source_override=
description_file=
pass_options=()
positionals=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --source)
      [[ $# -ge 2 ]] || { echo '--source에는 원본 루트가 필요합니다.' >&2; exit 64; }
      source_override=$2
      shift 2
      ;;
    --description|--description-file)
      [[ $# -ge 2 ]] || { echo "$1 옵션에는 값이 필요합니다." >&2; exit 64; }
      description_file=$2
      shift 2
      ;;
    --url|--port)
      [[ $# -ge 2 ]] || { echo "$1 옵션에는 값이 필요합니다." >&2; exit 64; }
      pass_options+=("$1" "$2")
      shift 2
      ;;
    --*) pass_options+=("$1"); shift ;;
    *) positionals+=("$1"); shift ;;
  esac
done
[[ ${#positionals[@]} -ge 1 ]] || { usage >&2; exit 64; }
challenge_name=${positionals[0]}
[[ "$challenge_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo '잘못된 문제 이름입니다.' >&2; exit 65; }
endpoint_args=("${positionals[@]:1}")

script_path=$(readlink -f -- "${BASH_SOURCE[0]}")
script_dir=$(cd -- "$(dirname -- "$script_path")" && pwd)
agent_root=${CTF_AGENT_ROOT:-$(cd -- "$script_dir/../.." && pwd)}
seeds_root=${CTF_SEEDS_ROOT:-/mnt/c/Users/JW/Desktop/agents/ctf_seeds}
case "$category" in
  pwn) source_root=${source_override:-${CTF_PWNABLE_SOURCE:-$seeds_root/pwn}} ;;
  rev) source_root=${source_override:-${CTF_REV_SOURCE:-$seeds_root/rev}} ;;
  web) source_root=${source_override:-${CTF_WEB_SOURCE:-$seeds_root/web}} ;;
esac
original_source="$source_root/$challenge_name"
original_zip="$source_root/$challenge_name.zip"
if [[ ! -d "$original_source" && ! -f "$original_zip" ]]; then
  printf '문제 원본을 찾지 못했습니다: %s 또는 %s\n' "$original_source" "$original_zip" >&2
  exit 66
fi
if [[ -n "$description_file" ]]; then
  [[ -f "$description_file" && -r "$description_file" ]] || { echo "문제 설명 파일을 읽을 수 없습니다: $description_file" >&2; exit 66; }
  comparison_description=$(<"$description_file")
else
  comparison_description=${CTF_CHALLENGE_DESCRIPTION:-}
fi

run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
run_root="$agent_root/benchmarks/comparisons/$category/$run_id"
compare_sources="$run_root/sources"
mkdir -p "$compare_sources"
plain_name="${challenge_name}__codex_${run_id//[^A-Za-z0-9]/_}"
claude_name="${challenge_name}__claude_${run_id//[^A-Za-z0-9]/_}"
if [[ -d "$original_source" ]]; then
  ln -s "$original_source" "$compare_sources/$plain_name"
  ln -s "$original_source" "$compare_sources/$claude_name"
else
  ln -s "$original_zip" "$compare_sources/$plain_name.zip"
  ln -s "$original_zip" "$compare_sources/$claude_name.zip"
fi

base_launcher="$script_dir/ctf-$category-start.sh"
claude_launcher=$(command -v "ctf-$category-mix" 2>/dev/null || true)
[[ -x "$base_launcher" && -n "$claude_launcher" ]] || { echo '비교용 런처를 찾을 수 없습니다.' >&2; exit 69; }
plain_work="$agent_root/challenges/$plain_name/work"
claude_work="$agent_root/challenges/$claude_name/work"
plain_log="$run_root/codex-only.log"
claude_log="$run_root/claude-codex.log"

case "$category" in
  pwn) source_env=CTF_PWNABLE_SOURCE ;;
  rev) source_env=CTF_REV_SOURCE ;;
  web) source_env=CTF_WEB_SOURCE ;;
esac

printf '[A/B] Codex 단독 시작: %s\n' "$plain_name"
plain_started=$(date +%s.%N)
set +e
env "$source_env=$compare_sources" CTF_CHALLENGE_DESCRIPTION="$comparison_description" \
  CTF_EXTRA_PROMPT="${comparison_description:+문제 설명: $comparison_description}" \
  CTF_USAGE_SUMMARY_FILE="$plain_work/compare-codex-usage.json" \
  "$base_launcher" --keep-workspace "${pass_options[@]}" "$plain_name" "${endpoint_args[@]}" 2>&1 | tee "$plain_log"
plain_status=${PIPESTATUS[0]}
set -e
plain_finished=$(date +%s.%N)

printf '\n[B/B] Claude→Codex 시작: %s\n' "$claude_name"
claude_started=$(date +%s.%N)
set +e
env "$source_env=$compare_sources" CTF_CHALLENGE_DESCRIPTION="$comparison_description" \
  "$claude_launcher" --keep-workspace "${pass_options[@]}" "$claude_name" "${endpoint_args[@]}" 2>&1 | tee "$claude_log"
claude_status=${PIPESTATUS[0]}
set -e
claude_finished=$(date +%s.%N)

plain_wall=$(python3 -c 'import sys; print(float(sys.argv[2])-float(sys.argv[1]))' "$plain_started" "$plain_finished")
claude_wall=$(python3 -c 'import sys; print(float(sys.argv[2])-float(sys.argv[1]))' "$claude_started" "$claude_finished")
report="$run_root/report.md"
python3 "$script_dir/ctf-compare-report.py" \
  --category "$category" --challenge "$challenge_name" \
  --plain-work "$plain_work" --claude-work "$claude_work" \
  --plain-log "$plain_log" --claude-log "$claude_log" \
  --plain-wall "$plain_wall" --claude-wall "$claude_wall" \
  --plain-status "$plain_status" --claude-status "$claude_status" --output "$report"
printf '비교 보고서: %s\n' "$report"

[[ $plain_status -eq 0 && $claude_status -eq 0 ]]
