#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
사용법: ctf-clean [--apply] [--caches] [문제이름]

기본 동작은 삭제하지 않는 미리보기입니다. --apply를 지정해야 정리합니다.
문제이름을 생략하면 완료된 모든 문제를 검사합니다.

정리 대상:
  - 외부 원본이 확인된 완료 문제의 중복 input/
  - evidence/audit/의 선택적 실행 로그
  - work/ 아래의 core dump, __pycache__, .pytest_cache
  - 외부 원본에서 재생성 가능한 work/runtime의 libc·ld 복사본
  - --caches 지정 시 재생성 가능한 go-build, pip, uv 사용자 캐시

항상 보존:
  - 모든 분야의 ctf-learn feedback
  - work/solve.py, work/writeup.md, 학습·풀이 완료 표식
  - work/runtime/runtime.env 런타임 출처·호환성 기록
  - evidence/private 및 scope
EOF
}

apply=false
clean_caches=false
challenge_name=

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) apply=true ;;
    --caches) clean_caches=true ;;
    -h|--help) usage; exit 0 ;;
    -*) printf '알 수 없는 옵션: %s\n' "$1" >&2; exit 64 ;;
    *)
      [[ -z "$challenge_name" ]] || { echo '문제 이름은 하나만 지정할 수 있습니다.' >&2; exit 64; }
      challenge_name=$1
      ;;
  esac
  shift
done

agent_root=${CTF_AGENT_ROOT:-$HOME/workspace/CTF/ctf-agent}
source_root=${CTF_PWNABLE_SOURCE:-$HOME/ctf-challenges/pwnable}
challenges_root="$agent_root/challenges"
reclaimed=0

[[ -d "$challenges_root" ]] || { printf 'challenges 경로가 없습니다: %s\n' "$challenges_root" >&2; exit 66; }

size_bytes() {
  du -sb -- "$1" 2>/dev/null | awk '{print $1}' || printf '0\n'
}

remove_exact() {
  local target=$1 allowed_root=$2 bytes=0 resolved allowed_resolved
  [[ -e "$target" || -L "$target" ]] || return 0
  resolved=$(readlink -m -- "$target")
  allowed_resolved=$(readlink -m -- "$allowed_root")
  case "$resolved" in
    "$allowed_resolved"/*) ;;
    *) printf '안전 경계 밖 대상은 거부합니다: %s\n' "$resolved" >&2; return 1 ;;
  esac
  bytes=$(size_bytes "$target")
  if [[ "$apply" == true ]]; then
    rm -rf -- "$target"
    printf '정리: %s (%s bytes)\n' "$target" "$bytes"
  else
    printf '정리 예정: %s (%s bytes)\n' "$target" "$bytes"
  fi
  reclaimed=$((reclaimed + bytes))
}

is_completed() {
  local dir=$1
  [[ -f "$dir/work/.solved" || -f "$dir/work/.learned" || ( -f "$dir/work/solve.py" && -f "$dir/work/writeup.md" ) || ( -f "$dir/work/recover.py" && -f "$dir/work/writeup.md" ) ]]
}

find_source() {
  local dir=$1 name=$2 recorded=
  if [[ -f "$dir/scope/source-path.txt" ]]; then
    IFS= read -r recorded < "$dir/scope/source-path.txt" || true
    if [[ -n "$recorded" && ( -d "$recorded" || -f "$recorded" ) ]]; then
      printf '%s\n' "$recorded"
      return 0
    fi
  fi
  if [[ -d "$source_root/$name" ]]; then
    printf '%s\n' "$source_root/$name"
    return 0
  fi
  if [[ -f "$source_root/$name.zip" ]]; then
    printf '%s\n' "$source_root/$name.zip"
    return 0
  fi
  return 1
}

runtime_is_recoverable() {
  local runtime_dir=$1 source_path=$2 runtime_source= libc_candidate= ld_candidate= archive_entries=
  [[ -f "$runtime_dir/runtime.env" ]] || return 1
  runtime_source=$(sed -n 's/^runtime_source=//p' "$runtime_dir/runtime.env" | sed -n '1p')
  case "$runtime_source" in
    supplied)
      if [[ -d "$source_path" ]]; then
        libc_candidate=$(find "$source_path" \( -type f -o -type l \) \
          \( -name libc.so.6 -o -name 'libc-[0-9]*.so*' \) -print -quit 2>/dev/null)
        ld_candidate=$(find "$source_path" \( -type f -o -type l \) \
          \( -name 'ld-linux*.so*' -o -name 'ld-*.so*' \) -print -quit 2>/dev/null)
        [[ -n "$libc_candidate" && -n "$ld_candidate" ]]
      elif [[ -f "$source_path" ]] && command -v unzip >/dev/null 2>&1; then
        archive_entries=$(unzip -Z1 -- "$source_path" 2>/dev/null || true)
        grep -Eq '(^|/)(libc\.so\.6|libc-[0-9][^/]*)$' <<< "$archive_entries" &&
          grep -Eq '(^|/)(ld-linux[^/]*\.so[^/]*|ld-[^/]*\.so[^/]*)$' <<< "$archive_entries"
      else
        return 1
      fi
      ;;
    image|mixed)
      if [[ -d "$source_path" ]]; then
        [[ -f "$source_path/Dockerfile" ]]
      elif [[ -f "$source_path" ]] && command -v unzip >/dev/null 2>&1; then
        unzip -Z1 -- "$source_path" 2>/dev/null | grep -Eq '(^|/)Dockerfile$'
      else
        return 1
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

compact_runtime_bundle() {
  local dir=$1 source_path=$2 runtime_dir="$1/work/runtime" target= old_status= env_tmp=
  [[ -d "$runtime_dir" ]] || return 0
  if ! runtime_is_recoverable "$runtime_dir" "$source_path"; then
    printf '보존(runtime): 정확한 libc·ld 쌍의 재생성 근거가 부족합니다.\n'
    return 0
  fi
  while IFS= read -r -d '' target; do
    remove_exact "$target" "$dir"
  done < <(find "$runtime_dir" -mindepth 1 -maxdepth 1 ! -name runtime.env ! -name .compacted -print0)
  if [[ "$apply" == true ]]; then
    old_status=$(sed -n 's/^runtime_status=//p' "$runtime_dir/runtime.env" | sed -n '1p')
    env_tmp=$(mktemp "$runtime_dir/.runtime-env.XXXXXX")
    awk '!/^runtime_status=/ && !/^prepared_runtime_status=/ && !/^runtime_assets=/' \
      "$runtime_dir/runtime.env" > "$env_tmp"
    printf 'prepared_runtime_status=%q\n' "${old_status:-unknown}" >> "$env_tmp"
    printf 'runtime_status=compacted\n' >> "$env_tmp"
    printf 'runtime_assets=removed-recoverable\n' >> "$env_tmp"
    mv -- "$env_tmp" "$runtime_dir/runtime.env"
    printf 'runtime-assets-compacted\n' > "$runtime_dir/.compacted"
  fi
}

clean_challenge() {
  local name=$1 dir="$challenges_root/$1" source_path= target=
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { printf '잘못된 문제 이름: %s\n' "$name" >&2; return 1; }
  [[ -d "$dir" ]] || return 0
  is_completed "$dir" || { printf '보존(미완료): %s\n' "$name"; return 0; }

  printf '\n[%s]\n' "$name"
  if source_path=$(find_source "$dir" "$name"); then
    printf '복구 가능한 원본: %s\n' "$source_path"
    compact_runtime_bundle "$dir" "$source_path"
    remove_exact "$dir/input" "$dir"
  else
    printf '보존(input): 외부 원본을 확인할 수 없습니다.\n'
  fi

  remove_exact "$dir/evidence/audit" "$dir"
  remove_exact "$dir/work/__pycache__" "$dir"
  remove_exact "$dir/work/.pytest_cache" "$dir"
  while IFS= read -r -d '' target; do
    remove_exact "$target" "$dir"
  done < <(find "$dir/work" -maxdepth 1 -type f \( -name core -o -name 'core.*' \) -print0 2>/dev/null)
  while IFS= read -r -d '' target; do
    remove_exact "$target" "$dir"
  done < <(find "$dir/work" -maxdepth 1 -type f -name '.writeup-draft.*.md' -print0 2>/dev/null)

  if [[ "$apply" == true ]]; then
    printf 'compacted\n' > "$dir/work/.compacted"
  fi
}

if [[ -n "$challenge_name" ]]; then
  clean_challenge "$challenge_name"
else
  while IFS= read -r -d '' dir; do
    clean_challenge "$(basename -- "$dir")"
  done < <(find "$challenges_root" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
fi

if [[ "$clean_caches" == true ]]; then
  printf '\n[재생성 가능한 사용자 캐시]\n'
  cache_root="$HOME/.cache"
  remove_exact "$cache_root/go-build" "$cache_root"
  remove_exact "$cache_root/pip" "$cache_root"
  remove_exact "$cache_root/uv" "$cache_root"
fi

printf '\n%s 합계: %s bytes\n' "$([[ "$apply" == true ]] && printf '정리' || printf '정리 예정')" "$reclaimed"
if [[ "$apply" == false ]]; then
  echo '실제 정리는 같은 명령에 --apply를 추가하세요.'
fi
