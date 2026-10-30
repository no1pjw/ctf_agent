#!/usr/bin/env bash

CTF_STREAM_UI_ENABLED=false

ctf_stream_ui_init() {
  local title=$1
  if [[ ${CTF_STREAM_UI:-true} == false || ${CTF_STREAM_UI:-true} == 0 || ! -t 1 ]]; then
    return 0
  fi
  CTF_STREAM_UI_ENABLED=true
  export CTF_STREAM_UI_ACTIVE=true
  ctf_stream_ui_stage 'START' "$title" '실시간 이벤트 스트림 준비 중'
}

ctf_stream_ui_stage() {
  local step=$1 title=$2 detail=${3:-}
  [[ "$CTF_STREAM_UI_ENABLED" == true ]] || return 0
  printf '\033[2J\033[H'
  printf '\033[1;36m╔══════════════════════════════════════════════════════════════════════╗\033[0m\n'
  printf '\033[1;36m║\033[0m  \033[1mCTF CLAUDE → CODEX\033[0m   %-47s \033[1;36m║\033[0m\n' "[$step]"
  printf '\033[1;36m╠══════════════════════════════════════════════════════════════════════╣\033[0m\n'
  printf '\033[1;36m║\033[0m  \033[1;33m%-66s\033[0m  \033[1;36m║\033[0m\n' "$title"
  printf '\033[1;36m║\033[0m  %-66s  \033[1;36m║\033[0m\n' "$detail"
  printf '\033[1;36m╚══════════════════════════════════════════════════════════════════════╝\033[0m\n\n'
}

ctf_stream_ui_note() {
  [[ "$CTF_STREAM_UI_ENABLED" == true ]] || return 0
  printf '\033[2m%s\033[0m\n' "$*"
}
