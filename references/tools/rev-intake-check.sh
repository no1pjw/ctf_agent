#!/usr/bin/env bash
set -euo pipefail

input_dir=${1:-}
[[ -n "$input_dir" && -d "$input_dir" ]] || {
  echo 'usage: rev-intake-check.sh INPUT_DIR' >&2
  exit 64
}
input_dir=$(readlink -e -- "$input_dir")

file_count=0
total_bytes=0
unsafe_links=0
declare -a candidates=()

while IFS= read -r -d '' path; do
  rel=${path#"$input_dir"/}
  if [[ -L "$path" ]]; then
    resolved=$(readlink -e -- "$path" 2>/dev/null || true)
    case "$resolved" in
      "$input_dir"/*) ;;
      *) printf 'unsafe_symlink=%q\n' "$rel"; unsafe_links=$((unsafe_links + 1)); continue ;;
    esac
  fi
  [[ -f "$path" ]] || continue
  file_count=$((file_count + 1))
  size=$(stat -c %s -- "$path" 2>/dev/null || printf 0)
  total_bytes=$((total_bytes + size))
  type=$(file -b -- "$path" 2>/dev/null || printf unknown)
  case "$type" in
    *ELF*|*PE32*|*Mach-O*|*Java\ class*|*.Net*|*WebAssembly*|*bytecode*|*archive*|*executable*|*shared\ object*|*script*)
      candidates+=("$rel|$size|$type")
      ;;
  esac
done < <(find "$input_dir" -mindepth 1 -print0)

printf 'input_root=%q\n' "$input_dir"
printf 'file_count=%d\ntotal_bytes=%d\nunsafe_symlink_count=%d\n' "$file_count" "$total_bytes" "$unsafe_links"
printf 'dockerfile=%s\n' "$([[ -f "$input_dir/Dockerfile" ]] && printf present || printf absent)"

limit=80
shown=0
for entry in "${candidates[@]}"; do
  (( shown < limit )) || break
  IFS='|' read -r rel size type <<< "$entry"
  printf 'artifact=%q size=%s type=%q\n' "$rel" "$size" "$type"
  if [[ "$type" == *ELF* ]] && command -v readelf >/dev/null 2>&1; then
    interp=$(readelf -l -- "$input_dir/$rel" 2>/dev/null | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p' | sed -n '1p')
    [[ -z "$interp" ]] || printf 'interpreter=%q artifact=%q\n' "$interp" "$rel"
  fi
  shown=$((shown + 1))
done
printf 'candidate_count=%d\ncandidate_shown=%d\n' "${#candidates[@]}" "$shown"
(( ${#candidates[@]} <= limit )) || printf 'candidate_truncated=true\n'
