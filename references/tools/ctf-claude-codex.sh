#!/usr/bin/env bash
set -euo pipefail

command_name=$(basename -- "$0")
case "$command_name" in
  ctf-pwn-mix) category=pwn ;;
  ctf-rev-mix) category=rev ;;
  ctf-web-mix) category=web ;;
  *) printf '이 스크립트는 ctf-{pwn,rev,web}-mix 이름으로 실행해야 합니다.\n' >&2; exit 64 ;;
esac

if [[ $# -eq 0 || ${1:-} == -h || ${1:-} == --help ]]; then
  printf '사용법: %s [기존 %s 옵션] 문제이름 [공식 endpoint]\n' "$command_name" "$category"
  printf '추가 옵션: --description FILE  문제 설명 Markdown/텍스트 첨부\n'
  printf '추가 옵션: --no-skill  Claude customization과 Codex 스킬·AGENTS 주입 없이 실행\n'
  printf 'UI 옵션: --no-stream-ui  기존 일반 스트림 출력 사용\n'
  printf '1단계 Claude 정적 분석 후 2단계 Codex가 solver/exploit을 완성합니다.\n'
  exit 0
fi

original_args=("$@")
base_args=()
positionals=()
prepare_args=()
description_file=
verbose=false
skill_enabled=${CTF_USE_SKILL:-true}
for ((index=0; index < ${#original_args[@]}; index++)); do
  argument=${original_args[index]}
  case "$argument" in
    --description|--description-file)
      (( index + 1 < ${#original_args[@]} )) || { echo "$argument 옵션에는 파일 경로가 필요합니다." >&2; exit 64; }
      description_file=${original_args[index+1]}
      ((index+=1))
      ;;
    --description=*|--description-file=*)
      description_file=${argument#*=}
      ;;
    --no-stream-ui)
      export CTF_STREAM_UI=false
      ;;
    --stream-ui)
      export CTF_STREAM_UI=true
      ;;
    --no-skill)
      skill_enabled=false
      base_args+=("$argument")
      prepare_args+=("$argument")
      ;;
    --skill)
      skill_enabled=true
      base_args+=("$argument")
      prepare_args+=("$argument")
      ;;
    --dry-run|--prepare-only)
      printf '%s에서는 %s 옵션을 사용할 수 없습니다.\n' "$command_name" "$argument" >&2
      exit 64
      ;;
    --extra-prompt)
      base_args+=("$argument")
      ;;
    --verbose)
      verbose=true
      base_args+=("$argument")
      ;;
    --audit)
      base_args+=("$argument")
      ;;
    --source|--url|--port)
      (( index + 1 < ${#original_args[@]} )) || { echo "$argument 옵션에는 값이 필요합니다." >&2; exit 64; }
      option_value=${original_args[index+1]}
      base_args+=("$argument" "$option_value")
      prepare_args+=("$argument" "$option_value")
      ((index+=1))
      ;;
    --*)
      base_args+=("$argument")
      prepare_args+=("$argument")
      ;;
    *)
      positionals+=("$argument")
      base_args+=("$argument")
      prepare_args+=("$argument")
      ;;
  esac
done

case "$skill_enabled" in
  true|1|yes|on) skill_enabled=true ;;
  false|0|no|off) skill_enabled=false ;;
  *) printf 'CTF_USE_SKILL은 true 또는 false여야 합니다: %s\n' "$skill_enabled" >&2; exit 65 ;;
esac
if [[ "$skill_enabled" == true ]]; then
  claude_context_args=()
else
  claude_context_args=(--safe-mode --disable-slash-commands)
fi

[[ ${#positionals[@]} -ge 1 ]] || { echo '문제 이름을 찾지 못했습니다.' >&2; exit 64; }
challenge_name=${positionals[0]}
[[ "$challenge_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo '잘못된 문제 이름입니다.' >&2; exit 65; }

script_path=$(readlink -f -- "${BASH_SOURCE[0]}")
script_dir=$(cd -- "$(dirname -- "$script_path")" && pwd)
stream_ui_tool="$script_dir/ctf-stream-ui.sh"
[[ -r "$stream_ui_tool" ]] || { printf '스트림 UI 도구가 없습니다: %s\n' "$stream_ui_tool" >&2; exit 66; }
source "$stream_ui_tool"
ctf_stream_ui_init "$command_name · $challenge_name"
agent_root=${CTF_AGENT_ROOT:-$(cd -- "$script_dir/../.." && pwd)}
base_launcher="$script_dir/ctf-$category-start.sh"
metrics_tool="$script_dir/ctf-claude-metrics.py"
claude_stream_tool="$script_dir/ctf-claude-stream.py"
claude_bin=${CLAUDE_BIN:-$(command -v claude 2>/dev/null || true)}
claude_model=${CTF_CLAUDE_MODEL:-claude-opus-4-6}
claude_effort=${CTF_CLAUDE_EFFORT:-max}
claude_timeout_seconds=${CTF_CLAUDE_TIMEOUT_SECONDS:-600}
challenge_dir="$agent_root/challenges/$challenge_name"
work_dir="$challenge_dir/work"
handoff_file="$work_dir/claude-handoff.md"
claude_events="$work_dir/claude-events-1.jsonl"
claude_summary="$work_dir/claude-usage-1.json"
codex_summary="$work_dir/codex-usage-1.json"
claude_stderr="$work_dir/claude-stderr-1.log"
claude_refusal_marker="$work_dir/.claude-refused-1"
started=$(date +%s.%N)

[[ -x "$base_launcher" ]] || { printf '기본 런처가 없습니다: %s\n' "$base_launcher" >&2; exit 66; }
[[ -x "$metrics_tool" ]] || { printf '합산 도구가 없습니다: %s\n' "$metrics_tool" >&2; exit 66; }
[[ -x "$claude_stream_tool" ]] || { printf 'Claude 스트림 도구가 없습니다: %s\n' "$claude_stream_tool" >&2; exit 66; }
[[ -n "$claude_bin" && -x "$claude_bin" ]] || { echo 'Claude Code CLI를 찾을 수 없습니다.' >&2; exit 69; }
[[ "$claude_timeout_seconds" =~ ^[1-9][0-9]*$ ]] || { echo 'CTF_CLAUDE_TIMEOUT_SECONDS는 1 이상의 정수여야 합니다.' >&2; exit 65; }

ctf_stream_ui_stage '1/3' '문제 작업공간 준비' "$challenge_name"
printf '[1/3] 문제 작업공간 준비: %s\n' "$challenge_name"
CTF_PREPARE_STATIC_ONLY=true "$base_launcher" --prepare-only "${prepare_args[@]}"
mkdir -p "$work_dir"
rm -f -- "$claude_refusal_marker" "$work_dir/.claude-refused-2"

problem_description="$work_dir/problem-description.md"
if [[ -n "$description_file" ]]; then
  [[ -r "$description_file" && -f "$description_file" ]] || { printf '문제 설명 파일을 읽을 수 없습니다: %s\n' "$description_file" >&2; exit 66; }
  cp -a -- "$description_file" "$problem_description"
elif [[ -n ${CTF_CHALLENGE_DESCRIPTION:-} ]]; then
  printf '%s\n' "$CTF_CHALLENGE_DESCRIPTION" > "$problem_description"
else
  detected_description=
  for candidate in description.md problem.md README.md readme.md description.txt problem.txt README.txt; do
    if [[ -f "$challenge_dir/input/$candidate" ]]; then detected_description="$challenge_dir/input/$candidate"; break; fi
  done
  if [[ -n "$detected_description" ]]; then
    cp -a -- "$detected_description" "$problem_description"
  else
    : > "$problem_description"
  fi
fi

static_report="$work_dir/claude-static-report.txt"
if [[ "$category" == pwn ]]; then
  binary_candidate=
  while IFS= read -r candidate; do
    if file --brief "$candidate" 2>/dev/null | grep -q '^ELF '; then binary_candidate=$candidate; break; fi
  done < <(find "$challenge_dir/input" -type f -size -32M -print 2>/dev/null | sort)
  if [[ -n "$binary_candidate" ]]; then
    timeout 30s "$script_dir/pwn-triage.sh" "$binary_candidate" > "$static_report" 2>&1 || true
  else
    cp -a -- "$work_dir/intake-exec.txt" "$static_report"
  fi
else
  cp -a -- "$work_dir/intake-exec.txt" "$static_report" 2>/dev/null || printf '정적 intake 없음\n' > "$static_report"
fi

case "$category" in
  pwn) specialist='취약 함수, 보호기법, leak/write/control-flow primitive, libc·loader 가정, 입출력 framing과 가장 짧은 exploit chain' ;;
  rev) specialist='검증 루틴, 상수와 데이터 흐름, 역변환식, 필요한 offset, 가장 짧은 flag 복원 절차' ;;
  web) specialist='소스의 route·권한·상태 흐름, 취약점 primitive, 최소 재현 요청 순서와 필요한 세션 조건' ;;
esac

claude_prompt=$(cat <<EOF
허가된 CTF 문제 '$challenge_name'의 1단계 정적 분석만 수행하라.
분야=$category, 문제 설명=$problem_description, 사전 생성 정적 보고서=$static_report, 입력=$challenge_dir/input, scope=$challenge_dir/scope.
사전 생성 보고서와 제공된 소스만 해석하여 다음 Codex가 확인할 파일·함수·입력 지점을 좁히는 Markdown handoff를 출력하라. exploit이나 공격 payload를 설계하지 마라.
반드시 포함: 관찰 사실, 확인할 코드 위치, 불확실한 가정, 다음 최저비용 정적 검사.
600단어 이내로 끝내고 후보는 최대 2개만 제시하라.
이 단계는 선행 triage다. 정적 명령은 최대 8회만 사용하고, 유력 가설 하나와 근거 및 다음 검증 절차가 확보되면 추가 분석 없이 즉시 handoff를 출력하라. 전체 구조 복원, 완전한 exploit 작성, 반복 decompile은 Codex에 맡겨라.
대상 바이너리나 서버를 실행하지 말고 원격 네트워크에 접속하지 말며 파일을 수정하지 마라. 웹 검색, write-up 검색, flag 제출도 금지한다. 최종 답변에는 handoff 본문만 출력하라.
EOF
)
if [[ "$skill_enabled" == false ]]; then
  claude_prompt+=$'\n분야 지침·feedback·playbook 파일은 열지 말고 위에 명시된 입력·보고서·scope만 사용하라.'
fi

ctf_stream_ui_stage '2/3' 'Claude 정적 triage' "model=$claude_model · effort=$claude_effort · limit=${claude_timeout_seconds}s · skill=$skill_enabled"
ctf_stream_ui_note "원본 이벤트: $claude_events"
printf '[2/3] Claude 분석 시작: model=%s effort=%s limit=%ss\n' "$claude_model" "$claude_effort" "$claude_timeout_seconds"
set +e
printf '%s\n' "$claude_prompt" | timeout --foreground --signal=INT --kill-after=10s "${claude_timeout_seconds}s" \
  "$claude_bin" -p --verbose --output-format stream-json --no-session-persistence \
  "${claude_context_args[@]}" \
  --model "$claude_model" --effort "$claude_effort" --permission-mode bypassPermissions \
  --dangerously-skip-permissions \
  2> "$claude_stderr" | python3 "$claude_stream_tool" --events "$claude_events" --handoff "$handoff_file" --summary "$claude_summary" --refusal-marker "$claude_refusal_marker" --partial-ok
pipeline_status=("${PIPESTATUS[@]}")
claude_status=${pipeline_status[1]}
claude_stream_status=${pipeline_status[2]}
set -e
if [[ $claude_status -eq 124 && $claude_stream_status -eq 0 ]]; then
  printf 'Claude가 %s초 제한에 도달해 부분 handoff로 Codex에 넘깁니다.\n' "$claude_timeout_seconds"
elif [[ $claude_status -ne 0 || $claude_stream_status -ne 0 ]]; then
  printf 'Claude 분석 실패(status=%s stream=%s):\n' "$claude_status" "$claude_stream_status" >&2
  tail -n 30 "$claude_stderr" >&2
  [[ $claude_status -eq 0 ]] || exit "$claude_status"
  exit "$claude_stream_status"
fi
if [[ "$verbose" == true ]]; then
  printf '\n--- Claude handoff ---\n'
  cat -- "$handoff_file"
  printf '%s\n' '--- handoff 끝 ---'
fi

ctf_stream_ui_stage '3/3' 'Codex 검증 및 solver 완성' "Claude handoff → bounded 검증 → 공식 endpoint"
ctf_stream_ui_note "Claude 전체 로그: $claude_events"
printf '[3/3] Codex 검증 및 solver 완성 시작\n'
[[ "$category" != pwn ]] || rm -f -- "$work_dir/.remote-placeholder-rejected"
if [[ -f "$claude_refusal_marker" ]]; then
  printf 'Claude가 분석을 거절했습니다. 재호출하지 않고 Codex가 직접 시작합니다.\n'
  handoff_instruction="Claude handoff는 거절문이므로 사용하지 마라. 문제 설명 $problem_description 와 정적 보고서 $static_report 에서 직접 시작해 solver/exploit을 완성하라."
else
  if [[ "$skill_enabled" == true ]]; then
    handoff_instruction="문제 설명은 $problem_description, Claude 1단계 분석은 $handoff_file 에 있다. 우선순위 힌트로만 사용하고 Claude 이벤트나 전체 증거를 다시 읽지 마라. 가장 유력한 후보 하나를 bounded probe 한 번으로 검증한 뒤 기존 분야 규칙에 따라 solver/exploit을 완성하라."
  else
    handoff_instruction="문제 설명은 $problem_description, Claude 1단계 분석은 $handoff_file 에 있다. 우선순위 힌트로만 사용하고 Claude 이벤트나 전체 증거를 다시 읽지 마라. 가장 유력한 후보 하나를 bounded probe 한 번으로 검증한 뒤 런처가 제공한 범위·격리·검증 조건만으로 solver/exploit을 완성하라."
  fi
fi
if [[ -n ${CTF_EXTRA_PROMPT:-} ]]; then
  handoff_instruction+=$'\n'"$CTF_EXTRA_PROMPT"
fi
set +e
CTF_EXTRA_PROMPT="$handoff_instruction" CTF_USAGE_SUMMARY_FILE="$codex_summary" \
  "$base_launcher" "${base_args[@]}"
codex_status=$?
set -e

claude_summaries=("$claude_summary")
codex_summaries=("$codex_summary")
codex_interrupted=false
if [[ $codex_status -eq 130 || $codex_status -eq 143 ]]; then
  codex_interrupted=true
  printf '\nCodex 실행이 사용자에 의해 중단됐습니다. Claude 재검토 없이 종료합니다.\n'
fi
placeholder_marker="$work_dir/.remote-placeholder-rejected"
codex_remote_retries=${CTF_CODEX_REMOTE_RETRIES:-2}
[[ "$codex_remote_retries" =~ ^[0-9]+$ ]] || { echo 'CTF_CODEX_REMOTE_RETRIES는 0 이상의 정수여야 합니다.' >&2; exit 65; }
remote_retry=0
while [[ "$category" == pwn && "$codex_interrupted" == false && -f "$placeholder_marker" ]] \
  && { [[ ! -f "$work_dir/.solved" ]] || [[ "$(<"$work_dir/.solved")" != verified ]]; } \
  && (( remote_retry < codex_remote_retries )); do
  ((remote_retry+=1))
  printf '\n로컬 exploit 체인은 성공했지만 원격 후보가 placeholder였습니다. Claude로 돌아가지 않고 Codex 원격 수정 %d/%d를 시작합니다.\n' "$remote_retry" "$codex_remote_retries"
  ctf_stream_ui_stage 'REMOTE' 'Codex 원격 검증 수정' "placeholder 거부 · ${remote_retry}/${codex_remote_retries}"
  codex_remote_summary="$work_dir/codex-usage-remote-$remote_retry.json"
  remote_instruction="로컬 exploit 체인은 이미 성공했다. pwn-remote-run.sh가 원격 출력 후보를 로컬 placeholder와 같다고 거부했고 표식은 $placeholder_marker 에 있다. Claude 재분석이나 로컬 취약점 재탐색으로 돌아가지 마라. solve.py가 원격에서 로컬 flag를 하드코딩·에코·오인식하는 경로와 로컬/원격 환경 차이만 점검하고, 실질적 수정 후 공식 endpoint에 bounded 원격 검증을 수행하라. placeholder를 FLAG로 출력하지 말고 실제 원격 응답에서 얻은 값만 성공 처리하라."
  set +e
  CTF_EXTRA_PROMPT="$remote_instruction" CTF_USAGE_SUMMARY_FILE="$codex_remote_summary" \
    "$base_launcher" "${base_args[@]}"
  codex_status=$?
  set -e
  codex_summaries+=("$codex_remote_summary")
  if [[ $codex_status -eq 130 || $codex_status -eq 143 ]]; then
    codex_interrupted=true
    printf '\nCodex 원격 수정이 사용자에 의해 중단됐습니다. Claude 재검토 없이 종료합니다.\n'
  fi
done

placeholder_unresolved=false
if [[ "$category" == pwn && -f "$placeholder_marker" ]] \
  && { [[ ! -f "$work_dir/.solved" ]] || [[ "$(<"$work_dir/.solved")" != verified ]]; }; then
  placeholder_unresolved=true
  codex_status=75
  printf '\n원격 placeholder 문제가 Codex 수정 %d회 후에도 남아 있습니다. 정적 분석 문제는 아니므로 Claude 재검토를 건너뜁니다.\n' "$remote_retry"
fi

if [[ "$codex_interrupted" == false && "$placeholder_unresolved" == false && ! -f "$claude_refusal_marker" ]] && { [[ ! -f "$work_dir/.solved" ]] || [[ "$(<"$work_dir/.solved")" != verified ]]; }; then
  printf '\nCodex가 검증 완료 상태를 만들지 못해 Claude 재검토를 시작합니다.\n'
  ctf_stream_ui_stage 'REVIEW' 'Claude 재검토' 'Codex 실패 산출물에서 수정 가설 1개 선택'
  revised_handoff="$work_dir/claude-handoff-revised.md"
  claude_events_2="$work_dir/claude-events-2.jsonl"
  claude_summary_2="$work_dir/claude-usage-2.json"
  codex_summary_2="$work_dir/codex-usage-2.json"
  claude_stderr_2="$work_dir/claude-stderr-2.log"
  retry_prompt=$(cat <<EOF
허가된 CTF 문제 '$challenge_name'의 2차 정적 재검토를 수행하라.
문제 설명=$problem_description, 이전 handoff=$handoff_file, Codex 작업=$work_dir, 입력=$challenge_dir/input, scope=$challenge_dir/scope.
Codex가 아직 work/.solved=verified를 만들지 못했다. 기존 handoff와 Codex가 만든 solver/recover 파일, 상태와 오류를 읽고 실패 원인을 구체적으로 진단하라.
잘못된 가정, 누락된 primitive·offset·route·framing을 바로잡고 다음 Codex가 실행할 수정 절차를 우선순위대로 Markdown handoff로 출력하라.
재검토도 선행 triage다. 정적 명령은 최대 6회만 사용하고 가장 가능성 높은 수정 하나를 고른 뒤 즉시 handoff를 출력하라.
대상 실행, 원격 접속, 파일 수정, 웹 검색, flag 제출은 금지한다. 최종 답변에는 수정된 handoff 본문만 출력하라.
EOF
  )
  if [[ "$skill_enabled" == false ]]; then
    retry_prompt+=$'\n분야 지침·feedback·playbook 파일은 열지 말고 위에 명시된 handoff·작업 파일·입력만 사용하라.'
  fi
  set +e
  printf '%s\n' "$retry_prompt" | timeout --foreground --signal=INT --kill-after=10s "${claude_timeout_seconds}s" \
    "$claude_bin" -p --verbose --output-format stream-json --no-session-persistence \
    "${claude_context_args[@]}" \
    --model "$claude_model" --effort "$claude_effort" --permission-mode bypassPermissions \
    --dangerously-skip-permissions \
    2> "$claude_stderr_2" | python3 "$claude_stream_tool" --events "$claude_events_2" --handoff "$revised_handoff" --summary "$claude_summary_2" --partial-ok
  pipeline_status=("${PIPESTATUS[@]}")
  claude_retry_status=${pipeline_status[1]}
  claude_retry_stream_status=${pipeline_status[2]}
  set -e
  if [[ ( $claude_retry_status -eq 0 || $claude_retry_status -eq 124 ) && $claude_retry_stream_status -eq 0 ]]; then
    [[ $claude_retry_status -ne 124 ]] || printf 'Claude 재검토가 %s초 제한에 도달해 부분 handoff를 사용합니다.\n' "$claude_timeout_seconds"
    claude_summaries+=("$claude_summary_2")
    [[ "$verbose" == false ]] || { printf '\n--- Claude 수정 handoff ---\n'; cat -- "$revised_handoff"; printf '%s\n' '--- 수정 handoff 끝 ---'; }
    printf '수정된 Claude handoff로 Codex를 한 번 더 실행합니다.\n'
    ctf_stream_ui_stage 'RETRY' 'Codex 최종 재시도' '수정 handoff → 최소 검증 → 종료'
    retry_instruction="Claude 재검토 결과가 $revised_handoff 에 있다. 이전 실패 원인을 먼저 확인하고 수정된 가설을 최소 검사한 뒤 solver/exploit을 완성하라."
    set +e
    CTF_EXTRA_PROMPT="$retry_instruction" CTF_USAGE_SUMMARY_FILE="$codex_summary_2" \
      "$base_launcher" "${base_args[@]}"
    codex_status=$?
    set -e
    codex_summaries+=("$codex_summary_2")
  else
    printf 'Claude 재검토 실패(status=%s stream=%s):\n' "$claude_retry_status" "$claude_retry_stream_status" >&2
    tail -n 30 "$claude_stderr_2" >&2
  fi
fi

python3 "$metrics_tool" combined --claude "${claude_summaries[@]}" --codex "${codex_summaries[@]}" --started "$started"
exit "$codex_status"
