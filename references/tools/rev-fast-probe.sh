#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 ]] || { echo 'usage: rev-fast-probe.sh INPUT_DIR' >&2; exit 64; }
input_dir=$1
[[ -d "$input_dir" ]] || { printf 'input directory not found: %s\n' "$input_dir" >&2; exit 66; }

max_bytes=${CTF_REV_PROBE_MAX_BYTES:-16384}
[[ "$max_bytes" =~ ^[0-9]+$ ]] && (( max_bytes >= 4096 && max_bytes <= 65536 )) || {
  echo 'CTF_REV_PROBE_MAX_BYTES must be 4096..65536' >&2
  exit 65
}

tmp=$(mktemp)
trap 'rm -f -- "$tmp"' EXIT
export LC_ALL=C

{
  echo '== inventory =='
  find "$input_dir" -maxdepth 2 -type f -printf '%P\t%s bytes\n' | sort | sed -n '1,80p'

  echo '== file types =='
  while IFS= read -r -d '' path; do
    printf '%s: ' "${path#"$input_dir"/}"
    file -b -- "$path" || true
  done < <(find "$input_dir" -maxdepth 2 -type f -print0 | sort -z | head -z -n 40)

  while IFS= read -r -d '' path; do
    readelf -hW "$path" >/dev/null 2>&1 || continue
    rel=${path#"$input_dir"/}
    echo "== ELF $rel =="
    readelf -hW "$path" | sed -n '/Class:/p;/Data:/p;/Type:/p;/Machine:/p;/Entry point address:/p'
    readelf -lW "$path" 2>/dev/null | sed -n '/INTERP/,+1p;/GNU_STACK/p;/GNU_RELRO/p' || true

    echo '-- decisive symbols --'
    { nm -anC "$path" 2>/dev/null || true; } |
      grep -Eai '(^|[[:space:]_])(main|flag|win|check|verify|valid|success|fail|decode|decrypt|transform|vm|dispatch)([[:space:]_]|$)' |
      sed -n '1,100p' || true

    echo '-- decisive strings --'
    { strings -a -t x -n 4 "$path" 2>/dev/null || true; } |
      grep -Eai 'flag|success|correct|wrong|fail|invalid|password|secret|usage|[A-Za-z][A-Za-z0-9_]{1,31}\{' |
      sed -n '1,100p' || true

    if { nm -an "$path" 2>/dev/null || true; } | awk '$3 == "main" { found=1 } END { exit !found }'; then
      echo '-- main slice --'
      objdump -drwC -Mintel --disassemble=main "$path" 2>/dev/null | sed -n '1,260p' || true
    else
      entry=$(readelf -hW "$path" | awk '/Entry point address:/ { print $4; exit }')
      if [[ "$entry" =~ ^0x[0-9a-fA-F]+$ ]]; then
        echo '-- entry slice --'
        start=$((entry))
        stop=$((start + 512))
        objdump -drwC -Mintel --start-address="$start" --stop-address="$stop" "$path" 2>/dev/null |
          sed -n '1,220p' || true
      fi
    fi
  done < <(find "$input_dir" -maxdepth 2 -type f -print0 | sort -z)

  echo '== non-ELF direct strings =='
  count=0
  while IFS= read -r -d '' path; do
    readelf -hW "$path" >/dev/null 2>&1 && continue
    printf -- '-- %s --\n' "${path#"$input_dir"/}"
    { strings -a -t x -n 4 "$path" 2>/dev/null || true; } |
      grep -Eai 'flag|success|correct|wrong|fail|invalid|password|secret|[A-Za-z][A-Za-z0-9_]{1,31}\{' |
      sed -n '1,60p' || true
    count=$((count + 1))
    (( count < 12 )) || break
  done < <(find "$input_dir" -maxdepth 2 -type f -print0 | sort -z)
} > "$tmp"

size=$(wc -c < "$tmp")
head -c "$max_bytes" "$tmp"
if (( size > max_bytes )); then
  printf '\n[probe output truncated: %d of %d bytes shown]\n' "$max_bytes" "$size"
fi
