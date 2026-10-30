#!/usr/bin/env bash
set -euo pipefail

command_name=$(basename -- "$0")
case "$command_name" in
  ctf-pwn-claude) category=pwn ;;
  ctf-rev-claude) category=rev ;;
  ctf-web-claude) category=web ;;
  *) echo 'ctf-{pwn,rev,web}-claude 이름으로 실행하세요.' >&2; exit 64 ;;
esac

if [[ $# -eq 0 || ${1:-} == -h || ${1:-} == --help ]]; then
  printf '사용법: %s [기존 %s 옵션] [--description FILE] 문제이름 [공식 endpoint]\n' "$command_name" "$category"
  printf '추가 옵션: --no-skill  Claude의 CLAUDE.md·skills·customization 없이 실행\n'
  printf 'Claude가 분석, solver 작성, 로컬·원격 검증까지 단독 수행합니다.\n'
  exit 0
fi

original_args=("$@")
prepare_args=()
positionals=()
description_file=
skill_enabled=${CTF_USE_SKILL:-true}
for ((index=0; index < ${#original_args[@]}; index++)); do
  argument=${original_args[index]}
  case "$argument" in
    --description|--description-file)
      (( index + 1 < ${#original_args[@]} )) || { echo "$argument 옵션에는 파일 경로가 필요합니다." >&2; exit 64; }
      description_file=${original_args[index+1]}
      ((index+=1))
      ;;
    --description=*|--description-file=*) description_file=${argument#*=} ;;
    --no-skill) skill_enabled=false; prepare_args+=("$argument") ;;
    --skill) skill_enabled=true; prepare_args+=("$argument") ;;
    --dry-run|--prepare-only) printf '%s에서는 %s 옵션을 사용할 수 없습니다.\n' "$command_name" "$argument" >&2; exit 64 ;;
    --source|--url|--port)
      (( index + 1 < ${#original_args[@]} )) || { echo "$argument 옵션에는 값이 필요합니다." >&2; exit 64; }
      value=${original_args[index+1]}
      prepare_args+=("$argument" "$value")
      ((index+=1))
      ;;
    --*) prepare_args+=("$argument") ;;
    *) positionals+=("$argument"); prepare_args+=("$argument") ;;
  esac
done

case "$skill_enabled" in
  true|1|yes|on) skill_enabled=true ;;
  false|0|no|off) skill_enabled=false ;;
  *) printf 'CTF_USE_SKILL은 true 또는 false여야 합니다: %s\n' "$skill_enabled" >&2; exit 65 ;;
esac

[[ ${#positionals[@]} -ge 1 ]] || { echo '문제 이름을 찾지 못했습니다.' >&2; exit 64; }
challenge_name=${positionals[0]}
[[ "$challenge_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo '잘못된 문제 이름입니다.' >&2; exit 65; }

script_path=$(readlink -f -- "${BASH_SOURCE[0]}")
script_dir=$(cd -- "$(dirname -- "$script_path")" && pwd)
agent_root=${CTF_AGENT_ROOT:-$(cd -- "$script_dir/../.." && pwd)}
base_launcher="$script_dir/ctf-$category-start.sh"
claude_stream_tool="$script_dir/ctf-claude-stream.py"
metrics_tool="$script_dir/ctf-claude-metrics.py"
claude_bin=${CLAUDE_BIN:-$(command -v claude 2>/dev/null || true)}
claude_model=${CTF_CLAUDE_MODEL:-claude-opus-4-6}
claude_effort=${CTF_CLAUDE_EFFORT:-max}
claude_timeout_seconds=${CTF_CLAUDE_TIMEOUT_SECONDS:-600}
challenge_dir="$agent_root/challenges/$challenge_name"
work_dir="$challenge_dir/work"
problem_description="$work_dir/problem-description.md"
events_file="$work_dir/claude-only-events.jsonl"
result_file="$work_dir/claude-only-result.md"
summary_file="$work_dir/claude-only-usage.json"
stderr_file="$work_dir/claude-only-stderr.log"
refusal_marker="$work_dir/.claude-only-refused"
started_monotonic=$(python3 -c 'import time; print(time.monotonic())')

[[ -x "$base_launcher" && -x "$claude_stream_tool" && -n "$claude_bin" && -x "$claude_bin" ]] || { echo 'Claude-only 실행 도구를 찾을 수 없습니다.' >&2; exit 69; }
[[ "$claude_timeout_seconds" =~ ^[1-9][0-9]*$ ]] || { echo 'CTF_CLAUDE_TIMEOUT_SECONDS는 1 이상의 정수여야 합니다.' >&2; exit 65; }

printf '[1/2] 문제 작업공간 준비: %s\n' "$challenge_name"
"$base_launcher" --prepare-only "${prepare_args[@]}"
mkdir -p "$work_dir"
if [[ -n "$description_file" ]]; then
  [[ -f "$description_file" && -r "$description_file" ]] || { echo "문제 설명 파일을 읽을 수 없습니다: $description_file" >&2; exit 66; }
  cp -a -- "$description_file" "$problem_description"
elif [[ -n ${CTF_CHALLENGE_DESCRIPTION:-} ]]; then
  printf '%s\n' "$CTF_CHALLENGE_DESCRIPTION" > "$problem_description"
elif [[ ! -f "$problem_description" ]]; then
  : > "$problem_description"
fi

export CTF_LOCAL_FLAG_DENYLIST="$work_dir/local-placeholder-flags.txt"
export CTF_PWN_SOLVED_MARKER="$work_dir/.solved"
export CTF_PWN_REMOTE_PLACEHOLDER_MARKER="$work_dir/.remote-placeholder-rejected"
target_text=${positionals[*]:1}
[[ -n "$target_text" ]] || target_text='없음(로컬 검증만 허용)'

if [[ "$skill_enabled" == true ]]; then
  case "$category" in
    pwn) task_instruction="pwn-agent/skills/SKILL.md를 따르고 work/solve.py를 완성하라. 문제 파일은 호스트에서 직접 실행하지 말고 준비된 Docker 이미지와 references/tools/pwn-run.sh만 사용하라. 공식 원격이 있으면 references/tools/pwn-remote-run.sh로만 검증하라. 로컬 placeholder flag는 성공으로 인정하거나 출력하지 마라." ;;
    rev) task_instruction="rev-agent/skills/SKILL.md를 따르고 work/recover.py를 완성하라. 동적 검증은 준비된 Docker 하니스만 사용하고 복원 결과를 정방향 검증하라." ;;
    web) task_instruction="web-agent/skills/SKILL.md를 따르고 work/solve.py를 완성하라. 로컬 서비스는 references/tools/web-runtime.sh와 기록된 loopback endpoint만 사용하라. 공식 원격 URL 외 다른 외부 origin에는 접속하지 마라." ;;
  esac
  claude_context_args=()
else
  case "$category" in
    pwn) task_instruction="분야 지침·feedback·playbook 파일은 열지 말고 work/solve.py를 완성하라. 문제 파일은 호스트에서 직접 실행하지 말고 준비된 Docker 이미지와 references/tools/pwn-run.sh만 사용하라. 공식 원격이 있으면 references/tools/pwn-remote-run.sh로만 검증하라. 로컬 placeholder flag는 성공으로 인정하거나 출력하지 마라." ;;
    rev) task_instruction="분야 지침·feedback·playbook 파일은 열지 말고 work/recover.py를 완성하라. 동적 검증은 준비된 Docker 하니스만 사용하고 복원 결과를 정방향 검증하라." ;;
    web) task_instruction="분야 지침·feedback·playbook 파일은 열지 말고 work/solve.py를 완성하라. 로컬 서비스는 references/tools/web-runtime.sh와 기록된 loopback endpoint만 사용하라. 공식 원격 URL 외 다른 외부 origin에는 접속하지 마라." ;;
  esac
  claude_context_args=(--safe-mode --disable-slash-commands)
fi

prompt=$(cat <<EOF
허가된 $category CTF '$challenge_name'을 Claude 단독으로 끝까지 풀어라.
입력=$challenge_dir/input, 작업=$work_dir, scope=$challenge_dir/scope, 문제 설명=$problem_description, 공식 대상=$target_text.
$task_instruction
외부 웹 검색, write-up 검색, scoreboard 제출, 범위 밖 호스트 접근, brute force와 flood는 금지한다.
호스트에 pip, apt, npm 등 패키지를 설치하지 마라. 필요한 의존성은 제공 Dockerfile 이미지나 기존 격리 하니스 안에서만 사용하라.
작업 시작과 주요 가설 변경, 로컬 검증, 원격 검증, 장시간 대기 전에 현재 하는 일과 다음 행동을 한국어 1~2문장으로 알려라.
검증된 실제 flag를 얻으면 work/.solved에 verified를 기록하고 FLAG=<값>을 출력하라. 실패하면 BLOCKED=<구체적 이유> 한 줄로 끝내라.
EOF
)

printf '[2/2] Claude 단독 풀이 시작: model=%s effort=%s limit=%ss skill=%s\n' \
  "$claude_model" "$claude_effort" "$claude_timeout_seconds" "$skill_enabled"
set +e
printf '%s\n' "$prompt" | timeout --foreground --signal=INT --kill-after=10s "${claude_timeout_seconds}s" \
  "$claude_bin" -p --verbose --output-format stream-json --no-session-persistence \
  "${claude_context_args[@]}" \
  --model "$claude_model" --effort "$claude_effort" --permission-mode bypassPermissions \
  --dangerously-skip-permissions \
  2> "$stderr_file" | python3 "$claude_stream_tool" --events "$events_file" \
    --handoff "$result_file" --summary "$summary_file" --refusal-marker "$refusal_marker"
pipeline_status=("${PIPESTATUS[@]}")
claude_status=${pipeline_status[1]}
stream_status=${pipeline_status[2]}
set -e

if [[ $claude_status -ne 0 && $claude_status -ne 124 ]]; then
  printf 'Claude 단독 풀이 실패(status=%s stream=%s):\n' "$claude_status" "$stream_status" >&2
  tail -n 30 "$stderr_file" >&2
elif [[ $stream_status -ne 0 ]]; then
  printf 'Claude가 최종 결과 없이 종료했습니다(stream=%s). 부분 출력을 성공으로 처리하지 않습니다.\n' "$stream_status" >&2
fi
python3 "$metrics_tool" claude-only --summary "$summary_file" --started-monotonic "$started_monotonic"
[[ $claude_status -eq 0 && $stream_status -eq 0 ]]
