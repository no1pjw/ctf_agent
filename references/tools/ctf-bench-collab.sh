#!/usr/bin/env bash
set -euo pipefail

collab_dir=${CTF_BENCH_COLLAB_DIR:-}
participant=${CTF_BENCH_VARIANT:-unknown}
[[ -n "$collab_dir" ]] || { echo 'CTF_BENCH_COLLAB_DIR가 설정되지 않았습니다.' >&2; exit 64; }
candidate_dir="$collab_dir/candidates"
mkdir -p -- "$candidate_dir"

usage() {
  printf '%s\n' \
    '사용법:' \
    '  ctf-bench-collab.sh publish 제목 내용' \
    '  ctf-bench-collab.sh list' \
    '  ctf-bench-collab.sh read 파일명'
}

case "${1:-}" in
  publish)
    [[ $# -ge 3 ]] || { usage >&2; exit 64; }
    title=$2
    shift 2
    body=$*
    stamp=$(date -u +%Y%m%dT%H%M%S%NZ)-$$
    temporary=$(mktemp "$candidate_dir/.${participant}.${stamp}.XXXXXX")
    {
      printf '# %s\n\n' "$title"
      printf -- '- participant: `%s`\n- published_utc: `%s`\n\n' "$participant" "$stamp"
      printf '%s\n' "$body"
    } > "$temporary"
    mv -- "$temporary" "$candidate_dir/${stamp}-${participant}.md"
    printf '%s\n' "$candidate_dir/${stamp}-${participant}.md"
    ;;
  list)
    find "$candidate_dir" -maxdepth 1 -type f -name '*.md' -printf '%f\n' | sort
    ;;
  read)
    [[ $# -eq 2 ]] || { usage >&2; exit 64; }
    name=$2
    [[ "$name" != */* && "$name" != *..* ]] || { echo '후보 파일 경로가 안전하지 않습니다.' >&2; exit 65; }
    file="$candidate_dir/$name"
    [[ -f "$file" ]] || { echo "후보 파일이 없습니다: $name" >&2; exit 66; }
    cat -- "$file"
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
