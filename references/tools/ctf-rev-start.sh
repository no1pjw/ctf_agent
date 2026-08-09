#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0 2>/dev/null || true

usage() {
  cat <<'EOF'
사용법: ctf-rev [옵션] 문제이름

실행 모드:
  (기본값)       짧은 Fast Probe 후 필요한 경우 Deep으로 전환
  --fast-only    제한된 정적 분석까지만 수행
  --deep         처음부터 전체 분석 수행

옵션:
  --source DIR      문제 폴더 또는 ZIP이 들어 있는 원본 디렉터리
  --keep-workspace  완료 후에도 중복 입력 파일을 보존
  --prepare-only    문제만 복사하고 Codex는 실행하지 않음
  --dry-run         경로와 Codex 프롬프트만 표시
  -h, --help        도움말 표시

환경 변수:
  CTF_REV_SOURCE       기본 원본 디렉터리
  CTF_AGENT_ROOT       설치된 ctf-agent 루트
  CTF_MIN_HOST_FREE_MB Windows 호스트 최소 여유 공간(MiB, 기본 4096)
  CODEX_BIN            Codex CLI 경로
  CTF_CODEX_MODEL      문제 풀이 모델(기본 gpt-5.6-sol)
  CTF_CODEX_REASONING_EFFORT  추론 강도(기본 ultra)
EOF
}

action=launch
solve_mode=adaptive
keep_workspace=false
source_root=${CTF_REV_SOURCE:-$HOME/ctf-challenges/reversing}
challenge_name=

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || { echo '--source 경로가 필요합니다.' >&2; exit 64; }
      source_root=$2
      shift 2
      continue
      ;;
    --fast-only) solve_mode=fast-only ;;
    --deep) solve_mode=deep ;;
    --keep-workspace) keep_workspace=true ;;
    --prepare-only) action=prepare-only ;;
    --dry-run) action=dry-run ;;
    -h|--help) usage; exit 0 ;;
    -*) printf '알 수 없는 옵션: %s\n' "$1" >&2; exit 64 ;;
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

agent_root=${CTF_AGENT_ROOT:-$HOME/workspace/CTF/ctf-agent}
source_dir="$source_root/$challenge_name"
source_zip="$source_root/$challenge_name.zip"
challenge_dir="$agent_root/challenges/$challenge_name"
input_dir="$challenge_dir/input"
work_dir="$challenge_dir/work"
scope_dir="$challenge_dir/scope"
evidence_dir="$challenge_dir/evidence"
tools_dir="$agent_root/references/tools"
codex_bin=${CODEX_BIN:-}
codex_model=${CTF_CODEX_MODEL:-gpt-5.6-sol}
codex_reasoning_effort=${CTF_CODEX_REASONING_EFFORT:-ultra}
image_slug=$(printf '%s' "$challenge_name" | tr '[:upper:]_.' '[:lower:]--')
image_name="ctf-rev-$image_slug:local"

[[ -d "$agent_root" ]] || { printf 'CTF Agent 루트가 없습니다: %s\n' "$agent_root" >&2; exit 66; }
[[ -d "$source_dir" || -f "$source_zip" ]] || {
  printf '문제를 찾을 수 없습니다:\n  %s\n  %s\n' "$source_dir" "$source_zip" >&2
  exit 67
}

case "$solve_mode" in
  adaptive) mode_text='Fast Probe를 먼저 수행하고 패킹·난독화·VM, 환경 불일치, 가설 2회 실패 또는 10분 소진 시 기존 결과를 유지한 채 Deep으로 전환하라.' ;;
  fast-only) mode_text='Fast Probe만 수행하라. 10분, 주요 명령 10개, 가설 3개를 상한으로 하고 미해결 시 정확한 다음 단계만 보고하라.' ;;
  deep) mode_text='P0~P6 전체 절차를 수행하되 기존 분석 결과를 재사용하고, 동적 실행은 검증된 격리 환경에서만 수행하라.' ;;
esac

if [[ -f "$source_dir/Dockerfile" || -f "$input_dir/Dockerfile" ]]; then
  runtime_mode=supplied-docker
  runtime_text="제공된 Dockerfile이 있다. references/tools/pwn-build.sh로 $image_name 이미지를 빌드하고, 실행은 references/tools/sandbox-run.sh $image_name 명령 형식의 network=none 경계 안에서만 수행하라."
else
  runtime_mode=static-only
  runtime_text='Dockerfile이 없으므로 STATIC-ONLY다. file/readelf/objdump/strings/nm 등 비실행 분석만 사용하고 원본이나 복사본 바이너리를 호스트에서 실행하지 마라. 동적 검증이 필수라면 임의 환경을 만들지 말고 blocker로 보고하라.'
fi

prompt=$(cat <<EOF
\$ctf-rev

허가된 로컬 리버싱 문제 '$challenge_name'을 분석하라.
- 입력: challenges/$challenge_name/input
- 설정: mode=$solve_mode, runtime=$runtime_mode
- 기준: AGENTS.md, rules/ruleset.md, rev-agent/skills/SKILL.md, rev-agent/docs/playbook.md
- 진행 언어: 사용자에게 보이는 설명과 최종 답변은 한국어
- 실행 정책: $runtime_text
- 분석 정책: $mode_text
- 결과: work/recover.py 또는 필요한 최소 복원 스크립트와 work/writeup.md만 기본 보존
- 검증: 후보 결과를 독립 재구현 또는 격리된 원본 실행으로 확인하고 negative control 하나를 포함
- 완료 표식: 결과를 실제 검증한 뒤에만 work/.solved에 verified 한 줄을 기록
- 금지: 호스트에서 문제 바이너리 실행, 네트워크 접근, 플래그 자동 제출, 무제한 brute force
EOF
)

if [[ "$action" == dry-run ]]; then
  printf '원본 폴더: %s\n원본 ZIP: %s\n작업 경로: %s\n모드: %s\n런타임: %s\nCodex 모델: %s\n추론 강도: %s\n완료 후 정리: %s\n\n%s\n' \
    "$source_dir" "$source_zip" "$challenge_dir" "$solve_mode" "$runtime_mode" \
    "$codex_model" "$codex_reasoning_effort" \
    "$([[ "$keep_workspace" == true ]] && printf '보존' || printf '자동')" "$prompt"
  exit 0
fi

min_host_free_mb=${CTF_MIN_HOST_FREE_MB:-4096}
[[ "$min_host_free_mb" =~ ^[0-9]+$ ]] || { echo 'CTF_MIN_HOST_FREE_MB는 0 이상의 정수여야 합니다.' >&2; exit 65; }
if [[ -d /mnt/c && "$min_host_free_mb" -gt 0 ]]; then
  host_free_kb=$(df -Pk /mnt/c | awk 'NR==2 {print $4}')
  if [[ "$host_free_kb" =~ ^[0-9]+$ ]] && (( host_free_kb < min_host_free_mb * 1024 )); then
    printf 'Windows 호스트 여유 공간이 %s MiB 미만이어서 복사를 중단합니다. 먼저 ctf-clean --caches --apply를 실행하세요.\n' "$min_host_free_mb" >&2
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
printf '리버싱 문제 준비 완료: %s\n' "$challenge_dir"

[[ "$action" != prepare-only ]] || exit 0

if [[ -z "$codex_bin" && -x "$HOME/.local/bin/codex" ]]; then
  codex_bin="$HOME/.local/bin/codex"
elif [[ -z "$codex_bin" ]]; then
  codex_bin=$(command -v codex 2>/dev/null || true)
fi
[[ -n "$codex_bin" ]] || { echo 'Codex CLI를 찾을 수 없습니다.' >&2; exit 69; }

cleanup_on_exit() {
  local status=$?
  trap - EXIT INT TERM HUP
  if [[ "$runtime_mode" == supplied-docker && -x "$tools_dir/pwn-cleanup.sh" ]]; then
    "$tools_dir/pwn-cleanup.sh" "$image_name" || true
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

set +e
"$codex_bin" -C "$agent_root" --model "$codex_model" \
  -c "model_reasoning_effort=\"$codex_reasoning_effort\"" \
  --sandbox danger-full-access --ask-for-approval never "$prompt"
status=$?
set -e
exit "$status"
