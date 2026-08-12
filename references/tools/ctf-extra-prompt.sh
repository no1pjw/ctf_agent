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
  printf '추가 프롬프트를 여러 줄로 입력하세요. 마지막 줄에 .end를 입력하거나 Ctrl+D로 종료합니다.\n' >&2
  printf '생략하려면 바로 .end를 입력하세요.\n> ' >&2
  extra_prompt=
  first_line=true
  while IFS= read -r line; do
    line=${line%$'\r'}
    if [[ "$line" == .end ]]; then
      break
    fi
    if [[ "$first_line" == true ]]; then
      extra_prompt=$line
      first_line=false
    else
      extra_prompt+=$'\n'"$line"
    fi
    printf '> ' >&2
  done
  printf '\n' >&2
fi

# Command substitution safely captures this value; callers append it as data
# and never evaluate it as shell code.
printf '%s' "$extra_prompt"
