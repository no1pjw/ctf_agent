#!/usr/bin/env bash

CTF_ELAPSED_PID=
CTF_ELAPSED_STARTED=0
CTF_ELAPSED_LABEL=
CTF_ELAPSED_ACTIVE=false
CTF_ELAPSED_TTY=false

ctf_elapsed_format() {
  local total=$1
  printf '%02d:%02d:%02d' "$((total / 3600))" "$(((total % 3600) / 60))" "$((total % 60))"
}

ctf_elapsed_start() {
  CTF_ELAPSED_LABEL=$1
  CTF_ELAPSED_STARTED=$(date +%s)
  CTF_ELAPSED_ACTIVE=true
  if [[ -t 1 ]]; then
    CTF_ELAPSED_TTY=true
    (
      trap 'exit 0' INT TERM HUP
      while :; do
        now=$(date +%s)
        elapsed=$((now - CTF_ELAPSED_STARTED))
        printf '\r\033[2K%s | 경과 %s' "$CTF_ELAPSED_LABEL" "$(ctf_elapsed_format "$elapsed")"
        sleep 1
      done
    ) &
    CTF_ELAPSED_PID=$!
  else
    printf '%s | 경과 00:00:00\n' "$CTF_ELAPSED_LABEL"
  fi
}

ctf_elapsed_stop() {
  [[ "$CTF_ELAPSED_ACTIVE" == true ]] || return 0
  local now elapsed formatted
  now=$(date +%s)
  elapsed=$((now - CTF_ELAPSED_STARTED))
  formatted=$(ctf_elapsed_format "$elapsed")
  if [[ -n "$CTF_ELAPSED_PID" ]]; then
    kill "$CTF_ELAPSED_PID" 2>/dev/null || true
    wait "$CTF_ELAPSED_PID" 2>/dev/null || true
    CTF_ELAPSED_PID=
  fi
  if [[ "$CTF_ELAPSED_TTY" == true ]]; then
    printf '\r\033[2K%s | 총 소요 %s\n' "$CTF_ELAPSED_LABEL" "$formatted"
  else
    printf '%s | 총 소요 %s\n' "$CTF_ELAPSED_LABEL" "$formatted"
  fi
  CTF_ELAPSED_ACTIVE=false
}
