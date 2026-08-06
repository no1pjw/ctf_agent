#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
사용법: ctf-learn [옵션] 문제이름

옵션:
  --category CATEGORY  분야 직접 지정: pwn, rev, web, crypto, forensics
  --dry-run            분야, 경로 및 Codex 프롬프트만 표시
  -h, --help           도움말 표시

분야 별칭: reversing -> rev / misc, osint, malware, ai-ml -> forensics
EOF
}

category=
action=run
challenge_name=

while [[ $# -gt 0 ]]; do
  case "$1" in
    --category)
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

완료된 CTF 문제 '$challenge_name'에서 이후에도 재사용할 수 있는 새 교훈만 선별하라.
분야: $category
검토할 문제 경로: $challenge_dir
수정이 허용된 피드백 경로: $feedback_dir

work의 write-up과 solver를 우선 검토하고 기존 index.md 및 관련 주제 문서와 중복을 확인하라. 읽기·검색 호출은 최대 6회로 제한하고, 핵심 주장이 불충분할 때만 정확히 알려진 최소 evidence 파일을 추가로 읽으며 input 전체를 열거하지 마라. 플래그, 문제명, 정확한 주소/offset/payload 등 문제 전용 정답은 저장하지 마라. 관찰로 검증되고 다른 문제에도 적용 가능하며 다음 저비용 확인법이 있는 내용만 기존 주제에 통합하거나 새 주제 문서로 추가하라. 새 교훈이 없으면 파일을 수정하지 마라. Git 상태를 확인하지 말고 실제 편집 여부만 보고하라. 문제를 다시 실행하거나 네트워크에 접속하지 말고, 사용자에게 보이는 설명은 한국어로 작성하라.
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
  --sandbox workspace-write --ask-for-approval never \
  exec --ephemeral --skip-git-repo-check "$prompt" 2>"$trace_file"
status=$?
set -e
if [[ $status -ne 0 ]]; then
  printf 'ctf-learn 실행이 실패했습니다. 마지막 진단 내용:\n' >&2
  tail -n 80 "$trace_file" >&2
  exit "$status"
fi
