#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 BINARY" >&2
  exit 64
fi

binary=$1
[[ -f "$binary" ]] || { echo "binary not found: $binary" >&2; exit 66; }

echo '## file'
file "$binary"
echo
echo '## mitigations'
if command -v checksec >/dev/null 2>&1; then
  checksec --file="$binary"
else
  readelf -lW "$binary" | sed -n '/GNU_STACK\|GNU_RELRO/p'
fi
echo
echo '## interesting symbols'
nm -an "$binary" 2>/dev/null | grep -Ei ' (main|win|flag|shell|backdoor|system)$' || true
echo
echo '## imported functions'
readelf -sW "$binary" | grep ' UND ' | sed -E 's/.* UND //' | sort -u || true
echo
echo '## main disassembly'
objdump -d -M intel --disassemble=main "$binary" 2>/dev/null || true
