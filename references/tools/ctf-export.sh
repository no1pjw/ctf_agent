#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
사용법: ctf-export [옵션]

옵션:
  -m, --message TEXT       로컬 Git 커밋 메시지
  -o, --output PATH        공개 준비본 경로(기본: ~/releases/ctf-agent-public-시간)
      --repo URL           원격 저장소 URL
      --push               로컬 커밋 후 main 브랜치를 원격으로 push
      --author-name NAME   커밋 작성자 이름
      --author-email MAIL  커밋 작성자 이메일
      --dry-run            복사·변경·커밋 없이 계획만 표시
  -h, --help               도움말 표시

커밋 메시지를 생략하면 대화형 터미널에서 입력을 요청합니다.
기본값은 push하지 않으며, --push를 명시해야 원격에 반영합니다.
EOF
}

source_dir=${CTF_AGENT_ROOT:-$HOME/workspace/CTF/ctf-agent}
repo_url=${CTF_EXPORT_REPO:-https://github.com/no1pjw/ctf_agent.git}
output_dir=
commit_message=
author_name=${CTF_EXPORT_AUTHOR_NAME:-$(git config --global user.name 2>/dev/null || true)}
author_email=${CTF_EXPORT_AUTHOR_EMAIL:-$(git config --global user.email 2>/dev/null || true)}
dry_run=false
push_enabled=false

for required_command in git realpath rg sed find cmp; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf '필수 명령을 찾을 수 없습니다: %s\n' "$required_command" >&2
    exit 63
  }
done

while [[ $# -gt 0 ]]; do
  case "$1" in
    --message=*) commit_message=${1#*=}; shift ;;
    -m|--message)
      [[ $# -ge 2 ]] || { echo '커밋 메시지가 필요합니다.' >&2; exit 64; }
      commit_message=$2
      shift 2
      ;;
    --output=*) output_dir=${1#*=}; shift ;;
    -o|--output)
      [[ $# -ge 2 ]] || { echo '출력 경로가 필요합니다.' >&2; exit 64; }
      output_dir=$2
      shift 2
      ;;
    --repo=*) repo_url=${1#*=}; shift ;;
    --repo)
      [[ $# -ge 2 ]] || { echo '저장소 URL이 필요합니다.' >&2; exit 64; }
      repo_url=$2
      shift 2
      ;;
    --push) push_enabled=true; shift ;;
    --author-name=*) author_name=${1#*=}; shift ;;
    --author-name)
      [[ $# -ge 2 ]] || { echo '작성자 이름이 필요합니다.' >&2; exit 64; }
      author_name=$2
      shift 2
      ;;
    --author-email=*) author_email=${1#*=}; shift ;;
    --author-email)
      [[ $# -ge 2 ]] || { echo '작성자 이메일이 필요합니다.' >&2; exit 64; }
      author_email=$2
      shift 2
      ;;
    --dry-run) dry_run=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf '알 수 없는 옵션: %s\n' "$1" >&2; usage >&2; exit 64 ;;
  esac
done

[[ "$repo_url" != *$'\n'* && -n "$repo_url" ]] || { echo '잘못된 저장소 URL입니다.' >&2; exit 65; }
if [[ -n "$commit_message" && "$commit_message" == *$'\n'* ]]; then
  echo '커밋 메시지는 한 줄이어야 합니다.' >&2
  exit 65
fi

source_real="$(realpath -e -- "$source_dir")"
if [[ -z "$output_dir" ]]; then
  output_dir="$HOME/releases/ctf-agent-public-$(date +%Y%m%d-%H%M%S)"
fi
output_real="$(realpath -m -- "$output_dir")"

case "$output_real/" in
  "$source_real/"*) echo '출력 경로는 원본 내부에 둘 수 없습니다.' >&2; exit 66 ;;
esac
[[ "$output_real" != / && "$output_real" != "$HOME" && "$output_real" != "$source_real" ]] || {
  echo '너무 넓거나 위험한 출력 경로입니다.' >&2
  exit 66
}
[[ ! -e "$output_real" && ! -L "$output_real" ]] || {
  printf '출력 경로가 이미 존재합니다. 덮어쓰지 않습니다: %s\n' "$output_real" >&2
  exit 67
}

copy_items=(
  .agents
  .claude
  feedback
  learn-agent
  mcp
  pwn-agent
  references
  rev-agent
  rules
  sandbox
  shimes
  web-agent
  writeup-agent
  install-wsl.sh
  README.md
)
for item in "${copy_items[@]}"; do
  [[ -e "$source_real/$item" || -L "$source_real/$item" ]] || {
    printf '필수 공개 항목이 없습니다: %s\n' "$item" >&2
    exit 68
  }
done

if [[ -z "$author_name" ]]; then
  author_name=no1pjw
fi
if [[ -z "$author_email" ]]; then
  author_email=no1pjw@users.noreply.github.com
fi

if [[ "$dry_run" == false && -z "$commit_message" ]]; then
  if [[ -t 0 ]]; then
    read -r -p '커밋 메시지: ' commit_message
  else
    echo '비대화형 실행에서는 -m/--message로 커밋 메시지를 지정하세요.' >&2
    exit 69
  fi
fi
[[ "$dry_run" == true || -n "$commit_message" ]] || { echo '커밋 메시지가 비어 있습니다.' >&2; exit 69; }

printf '원본(읽기 전용): %s\n' "$source_real"
printf '공개 준비본:     %s\n' "$output_real"
printf '원격 저장소:     %s\n' "$repo_url"
printf '커밋 작성자:     %s <%s>\n' "$author_name" "$author_email"
if [[ "$dry_run" == true ]]; then
  printf '커밋 메시지:     %s\n' "${commit_message:-(실행 시 입력)}"
  printf '제외: challenges 원본, state 내용, evidence, work, 바이너리, 플래그, 로그\n'
  if [[ "$push_enabled" == true ]]; then
    printf '동작: 원격 main clone → 공개 파일 동기화 → 민감정보 검사 → 커밋 → fast-forward push\n'
  else
    printf '동작: whitelist 복사 → 개인 경로 일반화 → 민감정보 검사 → 로컬 커밋\n'
  fi
  printf 'push: %s\n' "$([[ "$push_enabled" == true ]] && echo '요청됨' || echo '수행하지 않음')"
  exit 0
fi

before_manifest="$(mktemp /tmp/ctf-export-before.XXXXXX)"
after_manifest="$(mktemp /tmp/ctf-export-after.XXXXXX)"
trap 'rm -f -- "$before_manifest" "$after_manifest"' EXIT

make_manifest() {
  (
    cd "$source_real"
    find "${copy_items[@]}" -printf '%p\t%y\t%s\t%T@\n' | LC_ALL=C sort
  )
}
make_manifest > "$before_manifest"

mkdir -p -- "$(dirname -- "$output_real")"
if [[ "$push_enabled" == true ]]; then
  printf '원격 이력 가져오는 중: %s\n' "$repo_url"
  set +e
  git clone --origin origin -- "$repo_url" "$output_real"
  clone_status=$?
  set -e
  if [[ $clone_status -ne 0 ]]; then
    printf '원격 저장소 clone에 실패했습니다. 인증·URL·네트워크를 확인하세요.\n' >&2
    printf '불완전한 출력 경로가 남아 있을 수 있습니다: %s\n' "$output_real" >&2
    exit 73
  fi

  if git -C "$output_real" show-ref --verify --quiet refs/remotes/origin/main; then
    git -C "$output_real" checkout -B main origin/main >/dev/null
  elif git -C "$output_real" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "$output_real" checkout --orphan main >/dev/null
  else
    git -C "$output_real" symbolic-ref HEAD refs/heads/main
  fi
  managed_items=(
    "${copy_items[@]}"
    challenges
    state
    AGENTS.md
    CLAUDE.md
    .gitignore
  )
  git -C "$output_real" rm -r -f --ignore-unmatch -- "${managed_items[@]}" >/dev/null
else
  mkdir -- "$output_real"
fi
for item in "${copy_items[@]}"; do
  cp -a -- "$source_real/$item" "$output_real/"
done

mkdir -p -- "$output_real/challenges" "$output_real/state"
: > "$output_real/challenges/.gitkeep"
printf '# Notes\n\nProject-local notes. Do not commit flags, tokens, or personal data.\n' > "$output_real/state/notes.md"
printf '# Todo\n\n- [ ] Select an authorized local CTF challenge.\n' > "$output_real/state/todo.md"
ln -s shimes/AGENTS.md "$output_real/AGENTS.md"
ln -s shimes/CLAUDE.md "$output_real/CLAUDE.md"

cp -- "$source_real/references/export/gitignore.public" "$output_real/.gitignore"

pwn_launcher="$output_real/references/tools/ctf-pwn-start.sh"
web_launcher="$output_real/references/tools/ctf-web-start.sh"
rev_launcher="$output_real/references/tools/ctf-rev-start.sh"
bench_launcher="$output_real/references/tools/ctf-bench.sh"
public_readme="$output_real/README.md"
sed -i 's|^source_root=${CTF_PWNABLE_SOURCE:-.*}$|source_root=${CTF_PWNABLE_SOURCE:-$HOME/ctf-challenges/pwnable}|' "$pwn_launcher"
sed -i 's|^source_root=${CTF_WEB_SOURCE:-.*}$|source_root=${CTF_WEB_SOURCE:-$HOME/ctf-challenges/web}|' "$web_launcher"
sed -i 's|^source_root=${CTF_REV_SOURCE:-.*}$|source_root=${CTF_REV_SOURCE:-$HOME/ctf-challenges/rev}|' "$rev_launcher"
sed -i 's|^  pwn) source_root=${CTF_PWNABLE_SOURCE:-.*} ;;$|  pwn) source_root=${CTF_PWNABLE_SOURCE:-$HOME/ctf-challenges/pwnable} ;;|' "$bench_launcher"
sed -i 's|^  rev) source_root=${CTF_REV_SOURCE:-.*} ;;$|  rev) source_root=${CTF_REV_SOURCE:-$HOME/ctf-challenges/rev} ;;|' "$bench_launcher"
sed -i 's|^  web) source_root=${CTF_WEB_SOURCE:-.*} ;;$|  web) source_root=${CTF_WEB_SOURCE:-$HOME/ctf-challenges/web} ;;|' "$bench_launcher"

# Help text and README prose can contain the same machine-local defaults even
# after the executable assignment is normalized. Rewrite only the known CTF
# source roots; an unexpected personal path remains a blocking scan finding.
public_unix_desktop_pattern='/mnt/c/'"Users/[^/]+/OneDrive/Desktop"
public_home='$HOME'
for public_text in "$pwn_launcher" "$web_launcher" "$rev_launcher" "$bench_launcher" "$public_readme"; do
  sed -i -E \
    -e "s|$public_unix_desktop_pattern/pwnable|$public_home/ctf-challenges/pwnable|g" \
    -e "s|$public_unix_desktop_pattern/rev|$public_home/ctf-challenges/rev|g" \
    -e "s|$public_unix_desktop_pattern/web|$public_home/ctf-challenges/web|g" \
    "$public_text"
done

scan_output="$output_real/.ctf-export-scan.txt"
unix_user_pattern='/mnt/c/'"Users/"
windows_user_pattern='C:\\'"Users\\"
github_pat_pattern='github_'"pat_[A-Za-z0-9_]+"
github_classic_pattern='g'"hp_[A-Za-z0-9]+"
aws_key_pattern='AK'"IA[0-9A-Z]{16}"
private_key_pattern='BEGIN [A-Z ]*PRIVATE '"KEY"
credential_pattern='(^|[^A-Za-z])(password|passwd|api[_-]?key|secret[_-]?key)[[:space:]]*='
scan_pattern="$unix_user_pattern|$windows_user_pattern|$github_pat_pattern|$github_classic_pattern|$aws_key_pattern|$private_key_pattern|$credential_pattern"
set +e
rg -n -i "$scan_pattern" "$output_real" -g '!.git/**' > "$scan_output"
scan_status=$?
set -e
if [[ $scan_status -eq 0 ]]; then
  printf '공개본에서 개인 경로나 민감정보 후보를 발견했습니다:\n' >&2
  sed -n '1,80p' "$scan_output" >&2
  echo '공개본은 남겨 두었으며 커밋하지 않았습니다.' >&2
  exit 70
fi
if [[ $scan_status -ne 1 ]]; then
  printf '민감정보 검사가 실패했습니다(rg exit=%s). 공개본은 커밋하지 않습니다.\n' "$scan_status" >&2
  exit 70
fi
rm -f -- "$scan_output"

make_manifest > "$after_manifest"
if ! cmp -s -- "$before_manifest" "$after_manifest"; then
  echo '원본 메타데이터가 작업 중 변경되었습니다. 공개본은 커밋하지 않습니다.' >&2
  diff -u -- "$before_manifest" "$after_manifest" | sed -n '1,120p' >&2 || true
  exit 71
fi

if [[ "$push_enabled" == false ]]; then
  git -C "$output_real" init --initial-branch=main >/dev/null
  git -C "$output_real" remote add origin "$repo_url"
fi
git -C "$output_real" config user.name "$author_name"
git -C "$output_real" config user.email "$author_email"
git -C "$output_real" add -A

commit_created=true
if git -C "$output_real" diff --cached --quiet; then
  commit_created=false
else
  git -C "$output_real" commit -m "$commit_message" >/dev/null
fi

commit_id="$(git -C "$output_real" rev-parse --short HEAD 2>/dev/null || true)"
[[ -z "$(git -C "$output_real" status --short)" ]] || {
  echo '커밋 후 공개본 작업 트리가 깨끗하지 않습니다.' >&2
  exit 72
}

printf '\n공개 준비 완료\n'
printf '경로:   %s\n' "$output_real"
if [[ "$commit_created" == true ]]; then
  printf '커밋:   %s %s\n' "$commit_id" "$commit_message"
else
  printf '커밋:   변경 없음 (원격 main과 공개 내용이 동일함)\n'
fi
printf '원격:   %s\n' "$repo_url"
printf '원본은 수정되지 않았습니다.\n'

if [[ "$push_enabled" == true ]]; then
  printf '\n원격 push 시작: main -> origin\n'
  set +e
  git -C "$output_real" push --set-upstream origin main
  push_status=$?
  set -e
  if [[ $push_status -ne 0 ]]; then
    printf '\npush에 실패했습니다. 공개본과 로컬 커밋은 그대로 보존됩니다.\n' >&2
    printf 'GitHub 인증 또는 원격의 동시 변경 여부를 확인한 뒤 다음 명령으로 다시 시도하세요:\n' >&2
    printf '  git -C %q push --set-upstream origin main\n' "$output_real" >&2
    printf '강제 push는 자동으로 수행하지 않습니다.\n' >&2
    exit 73
  fi
  printf 'push 완료: %s (main)\n' "$repo_url"
else
  printf 'push는 수행하지 않았습니다. --push로 명시적으로 요청할 수 있습니다.\n'
fi
