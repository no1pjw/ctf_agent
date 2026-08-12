#!/usr/bin/env bash
set -euo pipefail

interactive=false
case ${1:-} in
  '') ;;
  --interactive) interactive=true ;;
  -h|--help)
    echo 'usage: ctf-extra-prompt.sh [--interactive]'
    exit 0
    ;;
  *) printf 'unknown option: %s\n' "$1" >&2; exit 64 ;;
esac

extra_prompt=${CTF_EXTRA_PROMPT:-}
if [[ "$interactive" == true ]]; then
  printf '추가 프롬프트를 한 줄로 입력하세요 (생략하려면 Enter): ' >&2
  if ! IFS= read -r extra_prompt; then
    echo >&2
    echo '추가 프롬프트 입력을 읽을 수 없습니다.' >&2
    exit 65
  fi
fi

# Command substitution safely captures this value; callers append it as data
# and never evaluate it as shell code.
printf '%s' "$extra_prompt"
