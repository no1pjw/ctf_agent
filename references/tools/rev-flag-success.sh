#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 ]] || { echo 'usage: rev-flag-success.sh FLAG' >&2; exit 64; }
flag=$1
work_dir=${CTF_REV_WORK_DIR:-}

[[ -n "$work_dir" && -d "$work_dir" ]] || {
  echo 'CTF_REV_WORK_DIR is unavailable.' >&2
  exit 66
}
[[ -n "$flag" && ${#flag} -le 4096 && "$flag" != *$'\n'* && "$flag" != *$'\r'* ]] || {
  echo 'invalid flag value' >&2
  exit 65
}
[[ "$flag" =~ ^[A-Za-z][A-Za-z0-9_]{0,31}\{[^{}[:cntrl:]]{1,4050}\}$ ]] || {
  echo 'invalid flag format: expected PREFIX{payload} without nested braces' >&2
  exit 65
}

result_tmp=$(mktemp "$work_dir/.flag-result.tmp.XXXXXX")
solved_tmp=$(mktemp "$work_dir/.solved.tmp.XXXXXX")
trap 'rm -f -- "$result_tmp" "$solved_tmp"' EXIT

printf 'FLAG=%s\n' "$flag" > "$result_tmp"
printf 'verified\n' > "$solved_tmp"
mv -f -- "$solved_tmp" "$work_dir/.solved"
mv -f -- "$result_tmp" "$work_dir/.flag-result"
trap - EXIT

printf 'FLAG=%s\n' "$flag"
