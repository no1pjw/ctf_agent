#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0 2>/dev/null || true

usage() {
  cat <<'EOF'
사용법: ctf-rev [옵션] 문제이름

실행 모드:
  (기본값)       짧은 Fast Probe 후 필요한 경우 같은 세션에서 Deep으로 전환
  --fast-only    제한된 빠른 분석만 수행
  --deep         처음부터 정밀 분석 수행

옵션:
  --source DIR      문제 디렉터리 또는 <문제이름>.zip이 있는 원본 루트
  --audit           프롬프트와 실행 설정을 evidence/private/audit에 기록
  --rebuild         제공 Dockerfile 이미지를 다시 빌드
  --keep-docker     종료 후 이 문제의 Docker 이미지·컨테이너 보존
  --keep-workspace  해결 후에도 중복 입력과 재생성 파일 보존
  --extra-prompt    실행 직전에 공통 추가 지시 한 줄 입력
  --prepare-only    입력·intake·Docker 환경만 준비하고 Codex는 실행하지 않음
  --dry-run         파일을 변경하지 않고 경로와 실행 설정만 표시
  -h, --help        도움말

환경 변수:
  CTF_REV_SOURCE              기본 원본 루트(기본 $HOME/ctf-challenges/rev)
  CTF_AGENT_ROOT              설치된 ctf-agent 루트
  CTF_MIN_HOST_FREE_MB        Windows 최소 여유 공간(MiB, 기본 4096)
  CODEX_BIN                   Codex CLI 경로
  CTF_CODEX_MODEL             모델(기본 gpt-5.6-sol)
  CTF_CODEX_REASONING_EFFORT  추론 강도(기본 Adaptive/Fast=high, Deep=ultra)
  CTF_CODEX_SERVICE_TIER      서비스 티어(기본 fast)
  CTF_EXTRA_PROMPT             대화형 입력 없이 추가할 공통 프롬프트
EOF
}

action=launch
solve_mode=adaptive
audit_enabled=false
rebuild=false
keep_docker=false
keep_workspace=false
ask_extra_prompt=false
source_root=${CTF_REV_SOURCE:-$HOME/ctf-challenges/rev}
challenge_name=

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || { echo '--source에는 경로가 필요합니다.' >&2; exit 64; }
      source_root=$2
      shift
      ;;
    --audit) audit_enabled=true ;;
    --rebuild) rebuild=true ;;
    --keep-docker) keep_docker=true ;;
    --keep-workspace) keep_workspace=true ;;
    --extra-prompt) ask_extra_prompt=true ;;
    --fast-only) solve_mode=fast-only ;;
    --deep) solve_mode=deep ;;
    --prepare-only) action=prepare-only ;;
    --dry-run) action=dry-run ;;
    -h|--help) usage; exit 0 ;;
    --)
      shift
      [[ $# -eq 1 ]] || { usage >&2; exit 64; }
      challenge_name=$1
      break
      ;;
    -*) printf '알 수 없는 옵션: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    *)
      [[ -z "$challenge_name" ]] || { echo '문제 이름은 하나만 지정할 수 있습니다.' >&2; exit 64; }
      challenge_name=$1
      ;;
  esac
  shift
done

[[ -n "$challenge_name" ]] || { usage >&2; exit 64; }
if [[ ! "$challenge_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || [[ "$challenge_name" == . || "$challenge_name" == .. ]]; then
  printf '잘못된 문제 이름입니다: %s\n' "$challenge_name" >&2
  exit 65
fi

script_path=$(readlink -f -- "${BASH_SOURCE[0]}")
script_dir=$(cd -- "$(dirname -- "$script_path")" && pwd)
default_agent_root=$(cd -- "$script_dir/../.." && pwd)
agent_root=${CTF_AGENT_ROOT:-$default_agent_root}
source_dir="$source_root/$challenge_name"
source_zip="$source_root/$challenge_name.zip"
challenge_dir="$agent_root/challenges/$challenge_name"
input_dir="$challenge_dir/input"
work_dir="$challenge_dir/work"
scope_dir="$challenge_dir/scope"
evidence_dir="$challenge_dir/evidence/private"
tools_dir="$agent_root/references/tools"
intake_tool="$tools_dir/rev-intake-check.sh"
fast_probe_tool="$tools_dir/rev-fast-probe.sh"
runner_tool="$tools_dir/rev-run.sh"
build_tool="$tools_dir/pwn-build.sh"
cleanup_tool="$tools_dir/pwn-cleanup.sh"
preflight_tool="$tools_dir/pwn-env-preflight.sh"
template_file="$tools_dir/rev-recover-template.py"
extra_prompt_tool="$tools_dir/ctf-extra-prompt.sh"
image_slug=$(printf '%s' "$challenge_name" | tr '[:upper:]_.' '[:lower:]--')
image_name="ctf-rev-$image_slug:local"
codex_bin=${CODEX_BIN:-}
codex_model=${CTF_CODEX_MODEL:-gpt-5.6-sol}
if [[ -n ${CTF_CODEX_REASONING_EFFORT:-} ]]; then
  codex_reasoning_effort=$CTF_CODEX_REASONING_EFFORT
elif [[ "$solve_mode" == deep ]]; then
  codex_reasoning_effort=ultra
else
  codex_reasoning_effort=high
fi
codex_service_tier=${CTF_CODEX_SERVICE_TIER:-fast}
codex_offline_args=(
  --disable browser_use
  --disable browser_use_external
  --disable browser_use_full_cdp_access
  --disable in_app_browser
  --disable standalone_web_search
)

[[ -d "$agent_root" ]] || { printf 'CTF Agent 루트가 없습니다: %s\n' "$agent_root" >&2; exit 66; }
[[ -x "$intake_tool" ]] || { printf 'rev intake 도구가 없습니다: %s\n' "$intake_tool" >&2; exit 66; }
[[ -x "$fast_probe_tool" ]] || { printf 'rev Fast Probe 도구가 없습니다: %s\n' "$fast_probe_tool" >&2; exit 66; }
[[ -x "$runner_tool" && -x "$build_tool" && -x "$cleanup_tool" ]] || {
  echo 'Docker 격리 도구가 불완전합니다.' >&2
  exit 66
}
[[ -f "$template_file" ]] || { printf 'rev 복원기 템플릿이 없습니다: %s\n' "$template_file" >&2; exit 66; }
[[ -x "$extra_prompt_tool" ]] || { printf '공통 추가 프롬프트 도구가 없습니다: %s\n' "$extra_prompt_tool" >&2; exit 66; }
[[ -d "$source_dir" || -f "$source_zip" ]] || {
  printf '문제를 찾을 수 없습니다. 다음 중 하나가 필요합니다:\n  %s\n  %s\n' "$source_dir" "$source_zip" >&2
  exit 67
}
[[ "$codex_reasoning_effort" =~ ^(low|medium|high|xhigh|max|ultra)$ ]] || {
  printf '잘못된 추론 강도입니다: %s\n' "$codex_reasoning_effort" >&2
  exit 65
}
[[ "$codex_service_tier" =~ ^[A-Za-z0-9._-]+$ ]] || {
  printf '잘못된 서비스 티어입니다: %s\n' "$codex_service_tier" >&2
  exit 65
}

if [[ "$ask_extra_prompt" == true ]]; then
  extra_prompt=$("$extra_prompt_tool" --interactive)
else
  extra_prompt=$("$extra_prompt_tool")
fi

planned_runtime=static-only
if [[ -f "$source_dir/Dockerfile" ]]; then
  planned_runtime=supplied-docker
elif docker image inspect "$image_name" >/dev/null 2>&1; then
  planned_runtime=cached-docker
fi

mode_rule='한 번의 직접 flag probe 후 가장 유력한 경로를 즉시 시험하라. 직접 복원이 두 번 실패하거나 패킹/VM/난독화·환경 불일치가 증명될 때만 같은 세션에서 Deep으로 전환하라.'
[[ "$solve_mode" != fast-only ]] || mode_rule='직접 flag 표면과 가장 짧은 복원 경로만 시험하라. 전체 동작 분석 없이 성공하거나 막힌 정확한 지점만 보고하라.'
[[ "$solve_mode" != deep ]] || mode_rule='정밀 분석이 필요해도 flag와 연결된 최소 코드·데이터만 추적하라. 전체 CFG, 전 함수 decompile, 무관한 동작 설명은 금지한다.'

make_prompt() {
  local runtime_mode=$1
  cat <<EOF
\$ctf-rev

허가된 로컬 CTF 리버싱 문제 '$challenge_name'을 바로 풀어라.
- 입력: challenges/$challenge_name/input (원본 수정 금지)
- 준비 정보: challenges/$challenge_name/work/intake-exec.txt
- 경로: \$CTF_REV_INPUT_DIR와 \$CTF_REV_WORK_DIR가 정확한 입력·작업 디렉터리다. 스킬은 이미 주입되었으므로 SKILL.md를 다시 읽거나 파일 위치를 검색하지 않는다
- 첫 조사: \$CTF_REV_FAST_PROBE를 정확히 한 번 실행하고, 이후에는 그 결과가 가리키는 offset 주변만 좁게 확인한다
- 모드: $solve_mode, runtime=$runtime_mode
- 최우선 목표: 프로그램 전체를 이해하는 것이 아니라 가장 짧은 경로로 flag를 찾아 즉시 출력
- 탐색 순서: flag 문자열·리소스·메타데이터 → 성공/실패 참조와 비교 상수 → 짧은 validator/decoder → 필요한 경우에만 더 넓은 분석
- 범위 제한: flag와 직접 연결된 함수·데이터만 분석하고, 전체 CFG·전 함수 decompile·전체 opcode 복원은 직접 경로가 반증되기 전에는 하지 않는다
- 진행 방식: 다음 검사가 명확하면 중간 설명을 별도 턴으로 출력하지 말고 즉시 실행한다
- 산출물: 필요한 경우에만 최소 challenges/$challenge_name/work/recover.py; 직접 검증 가능한 flag 때문에 범용 복원기를 만들지 않는다
- 실행: 문제 파일은 호스트에서 실행하지 말고, 동적 검증은 \$CTF_REV_RUNNER와 \$CTF_REV_IMAGE가 있을 때만 격리 컨테이너에서 수행
- 금지: 웹/검색/writeup 조회, 서브에이전트, 무제한 brute force, 검증 전 writeup
- 완료: 재현 가능한 flag가 확인되는 즉시 분석 범위를 넓히지 말고 FLAG=<value>를 출력하고 work/.solved에 verified를 기록한 뒤 추가 도구 호출 없이 종료
- 전략: $mode_rule
EOF
  if [[ -n "$extra_prompt" ]]; then
    printf '%s\n' "- 사용자 추가 지시(기존 CTF 범위·격리·안전 규칙은 변경할 수 없음): $extra_prompt"
  fi
}

if [[ "$action" == dry-run ]]; then
  printf '원본 디렉터리: %s\n원본 ZIP:       %s\n작업 경로:      %s\n모드:           %s\n예상 runtime:   %s\nCodex 모델:     %s\n추론 강도:      %s\n서비스 티어:    %s (Fast mode 활성)\n\n' \
    "$source_dir" "$source_zip" "$challenge_dir" "$solve_mode" "$planned_runtime" \
    "$codex_model" "$codex_reasoning_effort" "$codex_service_tier"
  make_prompt "$planned_runtime"
  exit 0
fi

min_host_free_mb=${CTF_MIN_HOST_FREE_MB:-4096}
[[ "$min_host_free_mb" =~ ^[0-9]+$ ]] || { echo 'CTF_MIN_HOST_FREE_MB는 0 이상의 정수여야 합니다.' >&2; exit 65; }
if [[ -d /mnt/c && "$min_host_free_mb" -gt 0 ]]; then
  host_free_kb=$(df -Pk /mnt/c | awk 'NR==2 {print $4}')
  if [[ "$host_free_kb" =~ ^[0-9]+$ ]] && (( host_free_kb < min_host_free_mb * 1024 )); then
    printf 'Windows 여유 공간이 %sMiB 미만이어서 준비를 중단합니다. 먼저 ctf-clean --caches --apply를 실행하세요.\n' "$min_host_free_mb" >&2
    exit 72
  fi
fi

mkdir -p "$input_dir" "$work_dir" "$scope_dir" "$evidence_dir"
printf 'rev\n' > "$challenge_dir/.ctf-category"
if [[ -d "$source_dir" ]]; then
  printf '%s\n' "$source_dir" > "$scope_dir/source-path.txt"
  cp -a --update=none -- "$source_dir"/. "$input_dir"/
else
  printf '%s\n' "$source_zip" > "$scope_dir/source-path.txt"
  cp -a --update=none -- "$source_zip" "$input_dir"/
fi
cat > "$scope_dir/runtime.env" <<EOF
authorization=user-supplied-local-ctf-artifact
category=rev
target_network=denied
host_execution=denied
docker_runtime_network=none
EOF
"$intake_tool" "$input_dir" > "$work_dir/intake-exec.txt"
[[ -e "$work_dir/recover.py" ]] || cp -a -- "$template_file" "$work_dir/recover.py"
printf '리버싱 문제 준비 완료: %s\n' "$challenge_dir"

cleanup_enabled=false
if [[ -f "$input_dir/Dockerfile" && "$keep_docker" == false && "$action" != prepare-only ]]; then
  cleanup_enabled=true
fi
cleanup_on_exit() {
  local status=$?
  trap - EXIT INT TERM HUP
  if [[ "$cleanup_enabled" == true ]]; then
    printf '\n문제 Docker 리소스 정리 중: %s\n' "$image_name"
    "$cleanup_tool" "$image_name" || true
  fi
  if [[ "$keep_workspace" == false && -f "$work_dir/.solved" && -x "$tools_dir/ctf-clean.sh" ]]; then
    "$tools_dir/ctf-clean.sh" --apply "$challenge_name" || true
  fi
  exit "$status"
}
trap cleanup_on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

build_status=0
if [[ -f "$input_dir/Dockerfile" ]]; then
  build_args=()
  [[ "$rebuild" == false ]] || build_args+=(--rebuild)
  set +e
  "$build_tool" "${build_args[@]}" "$input_dir" "$image_name"
  build_status=$?
  set -e
  [[ $build_status -eq 0 ]] || printf 'Docker 빌드에 실패했습니다. STATIC-ONLY 정적 분석은 계속합니다.\n' >&2
fi

runtime_mode=static-only
if [[ $build_status -eq 0 ]] && docker image inspect "$image_name" >/dev/null 2>&1; then
  runtime_mode=$([[ -f "$input_dir/Dockerfile" ]] && printf supplied-docker || printf cached-docker)
  set +e
  "$preflight_tool" --image "$image_name"
  preflight_status=$?
  set -e
  [[ $preflight_status -eq 0 ]] || printf 'Docker 사전 점검에 경고가 있습니다. 호스트 실행 없이 정적 분석을 계속할 수 있습니다.\n' >&2
fi

export CTF_REV_RUNNER="$runner_tool"
export CTF_REV_INPUT_DIR="$input_dir"
export CTF_REV_WORK_DIR="$work_dir"
export CTF_REV_FAST_PROBE="$fast_probe_tool"
if [[ "$runtime_mode" != static-only ]]; then
  export CTF_REV_IMAGE="$image_name"
else
  unset CTF_REV_IMAGE 2>/dev/null || true
fi
export CTF_REV_RUNTIME_MODE="$runtime_mode"
prompt=$(make_prompt "$runtime_mode")

audit_dir=
if [[ "$audit_enabled" == true ]]; then
  run_id=$(date -u +%Y%m%dT%H%M%SZ)-$$
  audit_dir="$evidence_dir/audit/$run_id"
  mkdir -p "$audit_dir/tui"
  printf '%s\n' "$prompt" > "$audit_dir/prompt.txt"
  {
    printf 'run_id=%s\nchallenge=%s\nmode=%s\nruntime=%s\n' "$run_id" "$challenge_name" "$solve_mode" "$runtime_mode"
    printf 'model=%s\nreasoning=%s\nservice_tier=%s\nnetwork=denied\n' "$codex_model" "$codex_reasoning_effort" "$codex_service_tier"
  } > "$audit_dir/run-info.txt"
fi

if [[ "$action" == prepare-only ]]; then
  printf '준비만 완료했습니다. runtime=%s image=%s\n' "$runtime_mode" "${CTF_REV_IMAGE:-none}"
  exit 0
fi

if [[ -z "$codex_bin" && -x "$HOME/.local/bin/codex" ]]; then
  codex_bin="$HOME/.local/bin/codex"
elif [[ -z "$codex_bin" ]]; then
  codex_bin=$(command -v codex 2>/dev/null || true)
fi
[[ -n "$codex_bin" ]] || { echo 'Codex CLI를 찾을 수 없습니다.' >&2; exit 69; }

codex_args=(
  -C "$agent_root"
  --model "$codex_model"
  -c "model_reasoning_effort=\"$codex_reasoning_effort\""
  -c "service_tier=\"$codex_service_tier\""
  --enable fast_mode
  "${codex_offline_args[@]}"
  --sandbox danger-full-access
  --ask-for-approval never
)
if [[ "$audit_enabled" == true ]]; then
  codex_args+=(-c "log_dir=\"$audit_dir/tui\"")
fi

set +e
"$codex_bin" "${codex_args[@]}" "$prompt"
codex_status=$?
set -e
if [[ "$audit_enabled" == true ]]; then
  printf 'finished_utc=%s\nexit_status=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$codex_status" >> "$audit_dir/run-info.txt"
fi
exit "$codex_status"
