#!/usr/bin/env bash
set -euo pipefail

command_name=$(basename -- "$0")
fixed_category=
case "$command_name" in
  ctf-learn-pwn) fixed_category=pwn ;;
  ctf-learn-rev) fixed_category=rev ;;
  ctf-learn-web) fixed_category=web ;;
  ctf-learn|ctf-learn.sh) ;;
  *) command_name=ctf-learn ;;
esac

usage() {
  if [[ -n "$fixed_category" ]]; then
    cat <<EOF
사용법: $command_name [옵션] 문제이름

이 명령은 분야가 '$fixed_category'로 고정되며 다른 Agent의 feedback을 수정하지 않습니다.

옵션:
  --dry-run            분야, 경로 및 Codex 프롬프트만 표시
  -h, --help           도움말 표시
EOF
    return
  fi
  cat <<'EOF'
사용법: ctf-learn [옵션] 문제이름

옵션:
  --category CATEGORY  분야 직접 지정: pwn, rev, web, crypto, forensics
  --dry-run            분야, 경로 및 Codex 프롬프트만 표시
  -h, --help           도움말 표시

분야 별칭: reversing -> rev / misc, osint, malware, ai-ml -> forensics
EOF
}

category=$fixed_category
action=run
challenge_name=

while [[ $# -gt 0 ]]; do
  case "$1" in
    --category)
      [[ -z "$fixed_category" ]] || {
        printf '%s은(는) 분야가 %s로 고정되어 --category를 사용할 수 없습니다.\n' "$command_name" "$fixed_category" >&2
        exit 64
      }
      [[ $# -ge 2 ]] || { echo '--category 값이 필요합니다.' >&2; exit 64; }
      category=$2
      shift 2
      ;;
    --dry-run) action=dry-run; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) printf '알 수 없는 옵션: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    *)
      [[ -z "$challenge_name" ]] || { echo '문제 이름은 하나만 지정할 수 있습니다.' >&2; exit 64; }
      challenge_name=$1
      shift
      ;;
  esac
done

[[ -n "$challenge_name" ]] || { usage >&2; exit 64; }
if [[ ! "$challenge_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || [[ "$challenge_name" == "." || "$challenge_name" == ".." ]]; then
  printf '잘못된 문제 이름입니다: %s\n' "$challenge_name" >&2
  exit 65
fi

agent_root=${CTF_AGENT_ROOT:-$HOME/workspace/CTF/ctf-agent}
challenge_dir="$agent_root/challenges/$challenge_name"
category_file="$challenge_dir/.ctf-category"
codex_bin=${CODEX_BIN:-}

[[ -d "$agent_root" ]] || { printf 'CTF Agent 루트가 존재하지 않습니다: %s\n' "$agent_root" >&2; exit 66; }
[[ -d "$challenge_dir" ]] || { printf '문제 작업 경로가 없습니다: %s\n' "$challenge_dir" >&2; exit 67; }
[[ -d "$challenge_dir/work" ]] || { printf '풀이 산출물 디렉터리가 없습니다: %s/work\n' "$challenge_dir" >&2; exit 68; }

if [[ -z "$category" && -f "$category_file" ]]; then
  category="$(tr -d '[:space:]' < "$category_file")"
fi

case "${category,,}" in
  pwn|pwnable) category=pwn; feedback_rel=pwn-agent/feedback ;;
  rev|reversing|reverse) category=rev; feedback_rel=rev-agent/feedback ;;
  web) category=web; feedback_rel=web-agent/feedback ;;
  crypto|cryptography) category=crypto; feedback_rel=feedback/crypto ;;
  forensics|forensic|misc|osint|malware|ai-ml|ai_ml) category=forensics; feedback_rel=feedback/forensics ;;
  '') printf '분야를 자동 확인할 수 없습니다. --category를 지정하세요.\n' >&2; exit 69 ;;
  *) printf '지원하지 않는 분야입니다: %s\n' "$category" >&2; exit 69 ;;
esac

feedback_dir="$agent_root/$feedback_rel"
[[ -f "$feedback_dir/index.md" ]] || { printf '피드백 색인이 없습니다: %s/index.md\n' "$feedback_dir" >&2; exit 70; }

prompt=$(cat <<EOF
\$ctf-learn
완료 문제 '$challenge_name'($category)의 work solver/write-up에서 새 일반 교훈만 $feedback_dir에 중복 없이 반영하라.
읽기는 6회 이하로 하고 문제 재실행·네트워크·input 전수 확인은 금지한다. flag, 문제명, 주소·offset·payload 등 정답은 저장하지 않는다.
재사용 가능하고 관찰로 검증되며 다음 저비용 확인법이 있는 내용만 기록한다. 새 교훈이 없으면 수정하지 말고 결과를 한국어 한 줄로 보고하라.
EOF
)

if [[ "$action" == dry-run ]]; then
  printf '문제:            %s\n' "$challenge_name"
  printf '분야:            %s\n' "$category"
  printf '문제 작업 경로:  %s\n' "$challenge_dir"
  printf '피드백 경로:     %s\n' "$feedback_dir"
  printf '\nCodex에 전달할 프롬프트:\n%s\n' "$prompt"
  exit 0
fi

if [[ -z "$codex_bin" && -x "$HOME/.local/bin/codex" ]]; then
  codex_bin="$HOME/.local/bin/codex"
elif [[ -z "$codex_bin" ]]; then
  codex_bin="$(command -v codex 2>/dev/null || true)"
fi
[[ -n "$codex_bin" ]] || { echo 'Codex CLI를 사용할 수 없습니다.' >&2; exit 71; }

printf '피드백 학습 시작: %s (%s)\n' "$challenge_name" "$category"
trace_file="$(mktemp /tmp/ctf-learn.XXXXXX.log)"
trap 'rm -f -- "$trace_file"' EXIT
set +e
"$codex_bin" -C "$feedback_dir" -c 'model_reasoning_effort="low"' \
  -c 'service_tier="fast"' --enable fast_mode \
  --sandbox workspace-write --ask-for-approval never \
  exec --ephemeral --skip-git-repo-check "$prompt" 2>"$trace_file"
status=$?
set -e
if [[ $status -ne 0 ]]; then
  printf 'ctf-learn 실행이 실패했습니다. 마지막 진단 내용:\n' >&2
  tail -n 80 "$trace_file" >&2
  exit "$status"
fi

printf 'learned\n' > "$challenge_dir/work/.learned"
printf '학습 기록 반영 완료: %s\n' "$feedback_dir"
if [[ -x "$agent_root/references/tools/ctf-clean.sh" ]]; then
  "$agent_root/references/tools/ctf-clean.sh" --apply "$challenge_name"
fi
