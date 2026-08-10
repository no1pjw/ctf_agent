#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: pwn-gadget-index.sh [--force] BINARY CACHE_DIR

Create or reuse one compact, Build-ID keyed gadget index for a challenge binary.
This helper is intentionally for the main challenge ELF. Search a supplied libc
only after a leak/base strategy exists, using a separate targeted query.
EOF
}

force=false
if [[ ${1-} == --force ]]; then
  force=true
  shift
fi
[[ $# -eq 2 ]] || { usage >&2; exit 64; }

binary=$1
cache_dir=$2
[[ -f "$binary" ]] || { printf 'binary not found: %s\n' "$binary" >&2; exit 66; }
ropgadget_bin=$(command -v ROPgadget 2>/dev/null || true)
if [[ -z "$ropgadget_bin" && -x "$HOME/.local/bin/ROPgadget" ]]; then
  ropgadget_bin="$HOME/.local/bin/ROPgadget"
fi
[[ -n "$ropgadget_bin" ]] || {
  echo 'ROPgadget is required for the bounded gadget index.' >&2
  exit 69
}
command -v readelf >/dev/null 2>&1 || { echo 'readelf is required.' >&2; exit 69; }
command -v timeout >/dev/null 2>&1 || { echo 'timeout is required.' >&2; exit 69; }

build_id=$(readelf -n -- "$binary" 2>/dev/null | awk '/Build ID:/ {print $3; exit}')
if [[ -n "$build_id" ]]; then
  cache_key=$build_id
  cacheable=true
else
  cache_key="no-build-id-$(stat -c '%s-%Y' -- "$binary")"
  cacheable=false
fi

mkdir -p -- "$cache_dir"
index="$cache_dir/gadgets-$cache_key.txt"
if [[ "$force" == false && "$cacheable" == true && -s "$index" ]]; then
  printf 'gadget_index=cache-hit\npath=%s\nbuild_id=%s\n' "$index" "$build_id"
  cat -- "$index"
  exit 0
fi

tmp=$(mktemp "$cache_dir/.gadgets.XXXXXX")
trap 'rm -f -- "$tmp" "$tmp.raw"' EXIT INT TERM HUP

set +e
timeout --signal=TERM --kill-after=2s 60s \
  "$ropgadget_bin" --binary "$binary" --depth 10 \
  --only 'pop|ret|leave|xchg|mov|add|sub|call|jmp|syscall' > "$tmp.raw" 2>&1
status=$?
set -e
if [[ $status -ne 0 ]]; then
  printf 'bounded ROPgadget probe failed (status=%s): %s\n' "$status" "$binary" >&2
  sed -n '1,20p' "$tmp.raw" >&2
  exit "$status"
fi

awk '
  /^0x[0-9a-fA-F]+ : / {
    line=$0
    print line
    total++
    if (line ~ /: leave ; ret/) pivot++
    if (line ~ /: pop rbp ; ret/) pop_rbp++
    if (line ~ /: pop rsp([ ;]|$)/ || line ~ /: xchg (r[a-z0-9]+, rsp|rsp, r[a-z0-9]+)/) direct_pivot++
    if (line ~ /: pop rdi ; ret/) pop_rdi++
    if (line ~ /: pop rsi ; ret/) pop_rsi++
    if (line ~ /: pop rdx ; ret/) pop_rdx++
    if (line ~ /: syscall([ ;]|$)/) syscall++
    if (line ~ /: (call|jmp) /) dispatch++
  }
  END {
    print "--- summary ---"
    printf "total_filtered=%d\n", total+0
    printf "leave_ret=%d\n", pivot+0
    printf "pop_rbp_ret=%d\n", pop_rbp+0
    printf "direct_pivot=%d\n", direct_pivot+0
    printf "pop_rdi_ret=%d\n", pop_rdi+0
    printf "pop_rsi_ret=%d\n", pop_rsi+0
    printf "pop_rdx_ret=%d\n", pop_rdx+0
    printf "syscall=%d\n", syscall+0
    printf "indirect_dispatch=%d\n", dispatch+0
  }
' "$tmp.raw" > "$tmp"

mv -f -- "$tmp" "$index"
trap - EXIT INT TERM HUP
rm -f -- "$tmp.raw"
printf 'gadget_index=generated\npath=%s\nbuild_id=%s\n' "$index" "${build_id:-unavailable}"
cat -- "$index"
