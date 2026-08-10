#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: pwn-runtime-prepare.sh --input DIR --output DIR [--image IMAGE] [--preserve-ready]

Prepare an immutable pwn runtime bundle. Supplied libc/loader files take
priority. Missing files may be copied from the exact already-built image.
The target and supplied inputs are never modified or executed.
EOF
}

input_dir=
output_dir=
image=
preserve_ready=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input) input_dir=${2:-}; shift 2 ;;
    --output) output_dir=${2:-}; shift 2 ;;
    --image) image=${2:-}; shift 2 ;;
    --preserve-ready) preserve_ready=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; usage >&2; exit 64 ;;
  esac
done

[[ -n "$input_dir" && -n "$output_dir" ]] || { usage >&2; exit 64; }
[[ -d "$input_dir" ]] || { printf 'input directory not found: %s\n' "$input_dir" >&2; exit 66; }
command -v readelf >/dev/null 2>&1 || { echo 'readelf is required' >&2; exit 69; }
command -v cmp >/dev/null 2>&1 || { echo 'cmp is required' >&2; exit 69; }

docker_bin=${CTF_DOCKER_BIN:-docker}
input_real=$(readlink -f -- "$input_dir")
output_parent=$(dirname -- "$output_dir")
mkdir -p -- "$output_parent"
output_parent_real=$(readlink -f -- "$output_parent")
output_real=$(readlink -m -- "$output_dir")
case "$output_real" in
  "$output_parent_real"/*) ;;
  *) printf 'unsafe runtime output path: %s\n' "$output_real" >&2; exit 65 ;;
esac
[[ "$output_real" != "$input_real" && "$output_real" != "$output_parent_real" ]] || {
  echo 'runtime output must be separate from input and its parent' >&2
  exit 65
}
case "$output_real" in
  "$input_real"/*) printf 'runtime output cannot be inside the input tree: %s\n' "$output_real" >&2; exit 65 ;;
esac
case "$input_real" in
  "$output_real"/*) printf 'runtime output cannot contain the input tree: %s\n' "$output_real" >&2; exit 65 ;;
esac

stage=$(mktemp -d "$output_parent_real/.pwn-runtime.XXXXXX")
container_id=

cleanup() {
  local status=$?
  trap - EXIT INT TERM HUP
  if [[ -n "$container_id" ]]; then
    "$docker_bin" rm -f -- "$container_id" >/dev/null 2>&1 || true
  fi
  if [[ -n "$stage" && -d "$stage" ]]; then
    rm -rf -- "$stage"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

elf_field() {
  local path=$1 label=$2
  LC_ALL=C readelf -h -- "$path" 2>/dev/null |
    awk -F: -v wanted="$label" '$1 ~ wanted {sub(/^[[:space:]]+/, "", $2); print $2; exit}'
}

elf_build_id() {
  LC_ALL=C readelf -n -- "$1" 2>/dev/null |
    sed -n 's/^[[:space:]]*Build ID:[[:space:]]*//p' | sed -n '1p'
}

elf_soname() {
  LC_ALL=C readelf -d -- "$1" 2>/dev/null |
    sed -n 's/.*(SONAME).*\[\([^]]*\)\].*/\1/p' | sed -n '1p'
}

elf_interpreter() {
  LC_ALL=C readelf -l -- "$1" 2>/dev/null |
    sed -n 's/.*Requesting program interpreter:[[:space:]]*\([^]]*\)].*/\1/p' | sed -n '1p'
}

is_elf() {
  readelf -h -- "$1" >/dev/null 2>&1
}

inside_input() {
  local resolved
  resolved=$(readlink -e -- "$1" 2>/dev/null || true)
  [[ -n "$resolved" ]] || return 1
  case "$resolved" in
    "$input_real"/*) printf '%s\n' "$resolved" ;;
    *) return 1 ;;
  esac
}

target_path=
target_score=999999
while IFS= read -r -d '' candidate; do
  is_elf "$candidate" || continue
  candidate_interp=$(elf_interpreter "$candidate")
  [[ -n "$candidate_interp" ]] || continue
  relative=${candidate#"$input_real"/}
  basename_candidate=$(basename -- "$candidate")
  case "$basename_candidate" in
    libc*.so*|ld*.so*|ynetd|socat) continue ;;
  esac
  depth=${relative//[^\/]/}
  score=${#depth}
  case "$basename_candidate" in
    chall|challenge|main|pwn|vuln) score=$((score - 20)) ;;
  esac
  if (( score < target_score )); then
    target_path=$candidate
    target_score=$score
  fi
done < <(find "$input_real" -type f -print0 | sort -z)

target_class=
target_machine=
target_data=
target_interpreter=
target_dir=
if [[ -n "$target_path" ]]; then
  target_class=$(elf_field "$target_path" 'Class')
  target_machine=$(elf_field "$target_path" 'Machine')
  target_data=$(elf_field "$target_path" 'Data')
  target_interpreter=$(elf_interpreter "$target_path")
  target_dir=$(dirname -- "$target_path")
fi

SELECTED=
SELECTED_ORIGIN=
SELECTED_AMBIGUOUS=false

select_supplied() {
  local kind=$1 candidate resolved base relative depth score best_score=999999
  local best= best_origin=
  SELECTED_AMBIGUOUS=false
  while IFS= read -r -d '' candidate; do
    resolved=$(inside_input "$candidate" || true)
    [[ -n "$resolved" ]] || continue
    base=$(basename -- "$candidate")
    case "$kind:$base" in
      libc:libc.so.6) score=0 ;;
      libc:libc-[0-9]*.so|libc:libc-[0-9]*.so.*|libc:libc.so) score=15 ;;
      ld:$(basename -- "$target_interpreter")) [[ -n "$target_interpreter" ]] || continue; score=0 ;;
      ld:ld-linux*.so*|ld:ld-*.so*|ld:ld-musl*.so*) score=15 ;;
      *) continue ;;
    esac
    is_elf "$resolved" || continue
    if [[ "$kind" == libc && "$(elf_soname "$resolved")" != libc.so.6 ]]; then
      continue
    fi
    if [[ -n "$target_machine" && "$(elf_field "$resolved" 'Machine')" != "$target_machine" ]]; then
      continue
    fi
    if [[ -n "$target_class" && "$(elf_field "$resolved" 'Class')" != "$target_class" ]]; then
      continue
    fi
    relative=${candidate#"$input_real"/}
    depth=${relative//[^\/]/}
    score=$((score + ${#depth}))
    [[ -z "$target_dir" || "$(dirname -- "$resolved")" != "$target_dir" ]] || score=$((score - 8))
    [[ "$relative" != deploy/* ]] || score=$((score - 4))
    if (( score < best_score )); then
      best=$resolved
      best_origin=$relative
      best_score=$score
      SELECTED_AMBIGUOUS=false
    elif (( score == best_score )) && [[ -n "$best" ]] && ! cmp -s -- "$best" "$resolved"; then
      SELECTED_AMBIGUOUS=true
    fi
  done < <(find "$input_real" \( -type f -o -type l \) -print0 | sort -z)
  SELECTED=$best
  SELECTED_ORIGIN=$best_origin
}

select_supplied libc
provided_libc=$SELECTED
provided_libc_origin=$SELECTED_ORIGIN
provided_libc_ambiguous=$SELECTED_AMBIGUOUS
select_supplied ld
provided_ld=$SELECTED
provided_ld_origin=$SELECTED_ORIGIN
provided_ld_ambiguous=$SELECTED_AMBIGUOUS

libc_paths=(
  /lib/x86_64-linux-gnu/libc.so.6 /usr/lib/x86_64-linux-gnu/libc.so.6 /lib64/libc.so.6
  /lib/i386-linux-gnu/libc.so.6 /usr/lib/i386-linux-gnu/libc.so.6 /lib32/libc.so.6
  /lib/aarch64-linux-gnu/libc.so.6 /usr/lib/aarch64-linux-gnu/libc.so.6
  /lib/arm-linux-gnueabihf/libc.so.6 /usr/lib/arm-linux-gnueabihf/libc.so.6
  /lib/riscv64-linux-gnu/libc.so.6 /usr/lib/riscv64-linux-gnu/libc.so.6
)
ld_paths=()
[[ -z "$target_interpreter" ]] || ld_paths+=("$target_interpreter")
ld_paths+=(
  /lib64/ld-linux-x86-64.so.2 /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2
  /lib/ld-linux.so.2 /lib/i386-linux-gnu/ld-linux.so.2
  /lib/ld-linux-aarch64.so.1 /lib/aarch64-linux-gnu/ld-linux-aarch64.so.1
  /lib/ld-linux-armhf.so.3 /lib/arm-linux-gnueabihf/ld-linux-armhf.so.3
  /lib/ld-linux-riscv64-lp64d.so.1 /lib/riscv64-linux-gnu/ld-linux-riscv64-lp64d.so.1
)

image_libc=
image_libc_origin=
image_ld=
image_ld_origin=
image_id=

docker_copy_first() {
  local kind=$1 destination=$2 path candidate_machine candidate_class
  shift 2
  for path in "$@"; do
    rm -f -- "$destination"
    if "$docker_bin" cp -L "$container_id:$path" "$destination" >/dev/null 2>&1; then
      is_elf "$destination" || continue
      candidate_machine=$(elf_field "$destination" 'Machine')
      candidate_class=$(elf_field "$destination" 'Class')
      [[ -z "$target_machine" || "$candidate_machine" == "$target_machine" ]] || continue
      [[ -z "$target_class" || "$candidate_class" == "$target_class" ]] || continue
      DOCKER_ORIGIN=$path
      return 0
    fi
  done
  rm -f -- "$destination"
  return 1
}

supplied_pair_compatible=false
if [[ "$provided_libc_ambiguous" == false && "$provided_ld_ambiguous" == false &&
      -n "$provided_libc" && -n "$provided_ld" &&
      "$(elf_field "$provided_libc" 'Machine')" == "$(elf_field "$provided_ld" 'Machine')" &&
      "$(elf_field "$provided_libc" 'Class')" == "$(elf_field "$provided_ld" 'Class')" &&
      "$(dirname -- "$provided_libc")" == "$(dirname -- "$provided_ld")" ]]; then
  supplied_pair_compatible=true
fi

need_image=true
[[ "$supplied_pair_compatible" == false ]] || need_image=false

if [[ "$need_image" == true && -n "$image" ]] && command -v "$docker_bin" >/dev/null 2>&1 &&
   "$docker_bin" image inspect "$image" >/dev/null 2>&1; then
  image_id=$("$docker_bin" image inspect --format '{{.Id}}' "$image" 2>/dev/null | sed -n '1p')
  [[ -n "$image_id" ]] || image_id=$image
  container_id=$("$docker_bin" create --network none --entrypoint /bin/true "$image_id")
  if docker_copy_first libc "$stage/.image-libc.so.6" "${libc_paths[@]}"; then
    image_libc="$stage/.image-libc.so.6"
    image_libc_origin=$DOCKER_ORIGIN
  fi
  if docker_copy_first ld "$stage/.image-ld.so" "${ld_paths[@]}"; then
    image_ld="$stage/.image-ld.so"
    image_ld_origin=$DOCKER_ORIGIN
  fi
fi

same_artifact() {
  local left=$1 right=$2 left_id right_id
  left_id=$(elf_build_id "$left")
  right_id=$(elf_build_id "$right")
  if [[ -n "$left_id" && -n "$right_id" ]]; then
    [[ "$left_id" == "$right_id" ]]
  else
    cmp -s -- "$left" "$right"
  fi
}

status=unavailable
runtime_source=none
pair_status=none
reason='libc and loader were not supplied and no exact image pair was available'
libc_origin=
ld_origin=
analysis_libc_rel=
local_libc_rel=
local_ld_rel=

if [[ "$provided_libc_ambiguous" == true || "$provided_ld_ambiguous" == true ]]; then
  status=ambiguous
  runtime_source=supplied
  pair_status=supplied-candidates-differ
  reason='multiple equally ranked supplied runtime candidates differ'
  if [[ -n "$image_libc" && -n "$image_ld" ]]; then
    mkdir -p "$stage/image"
    mv -- "$image_libc" "$stage/image/libc.so.6"
    mv -- "$image_ld" "$stage/image/ld.so"
    image_libc=
    image_ld=
    runtime_source=mixed
    pair_status=supplied-ambiguous-image-pair-kept-separate
    local_libc_rel=image/libc.so.6
    local_ld_rel=image/ld.so
    reason='supplied candidates are ambiguous; the exact image pair was kept separate'
  fi
elif [[ -n "$provided_libc" && -n "$provided_ld" ]]; then
  libc_origin="supplied:$provided_libc_origin"
  ld_origin="supplied:$provided_ld_origin"
  analysis_libc_rel=provided/libc.so.6
  if [[ "$supplied_pair_compatible" == true ]]; then
    cp -L -- "$provided_libc" "$stage/libc.so.6"
    cp -L -- "$provided_ld" "$stage/ld.so"
    status=ready
    runtime_source=supplied
    pair_status=same-source
    reason='supplied libc and loader pair selected'
    analysis_libc_rel=libc.so.6
    local_libc_rel=libc.so.6
    local_ld_rel=ld.so
  elif [[ -n "$image_libc" && -n "$image_ld" ]]; then
    mkdir -p "$stage/provided" "$stage/image"
    cp -L -- "$provided_libc" "$stage/provided/libc.so.6"
    cp -L -- "$provided_ld" "$stage/provided/ld.so"
    mv -- "$image_libc" "$stage/image/libc.so.6"
    mv -- "$image_ld" "$stage/image/ld.so"
    image_libc=
    image_ld=
    status=incompatible
    runtime_source=mixed
    pair_status=supplied-pair-unverified-image-pair-kept-separate
    reason='supplied libc and loader were not a same-directory pair; the exact image pair was kept separate'
    local_libc_rel=image/libc.so.6
    local_ld_rel=image/ld.so
  else
    mkdir -p "$stage/provided"
    cp -L -- "$provided_libc" "$stage/provided/libc.so.6"
    cp -L -- "$provided_ld" "$stage/provided/ld.so"
    status=incompatible
    runtime_source=supplied
    pair_status=supplied-pair-unverified
    reason='supplied libc and loader were not a verified same-directory architecture pair'
  fi
elif [[ -z "$provided_libc" && -z "$provided_ld" && -n "$image_libc" && -n "$image_ld" ]]; then
  mv -- "$image_libc" "$stage/libc.so.6"
  mv -- "$image_ld" "$stage/ld.so"
  image_libc=
  image_ld=
  status=ready
  runtime_source=image
  pair_status=same-source
  reason='libc and loader extracted from the exact image'
  libc_origin="image:$image_libc_origin"
  ld_origin="image:$image_ld_origin"
  analysis_libc_rel=libc.so.6
  local_libc_rel=libc.so.6
  local_ld_rel=ld.so
elif [[ -n "$provided_libc" && -z "$provided_ld" ]]; then
  mkdir -p "$stage/provided"
  cp -L -- "$provided_libc" "$stage/provided/libc.so.6"
  analysis_libc_rel=provided/libc.so.6
  libc_origin="supplied:$provided_libc_origin"
  if [[ -n "$image_libc" && -n "$image_ld" ]] && same_artifact "$provided_libc" "$image_libc"; then
    cp -L -- "$provided_libc" "$stage/libc.so.6"
    mv -- "$image_ld" "$stage/ld.so"
    image_ld=
    status=ready
    runtime_source=mixed
    pair_status=provided-libc-matches-image
    reason='supplied libc matches image libc; image loader completed the pair'
    ld_origin="image:$image_ld_origin"
    analysis_libc_rel=libc.so.6
    local_libc_rel=libc.so.6
    local_ld_rel=ld.so
  elif [[ -n "$image_libc" && -n "$image_ld" ]]; then
    mkdir -p "$stage/image"
    mv -- "$image_libc" "$stage/image/libc.so.6"
    mv -- "$image_ld" "$stage/image/ld.so"
    image_libc=
    image_ld=
    status=incompatible
    runtime_source=mixed
    pair_status=provided-libc-differs-from-image
    reason='supplied libc differs from image libc; the two pairs were kept separate'
    local_libc_rel=image/libc.so.6
    local_ld_rel=image/ld.so
  else
    status=partial
    runtime_source=supplied
    pair_status=libc-only
    reason='supplied libc found but a verified matching loader is unavailable'
  fi
elif [[ -z "$provided_libc" && -n "$provided_ld" ]]; then
  mkdir -p "$stage/provided"
  cp -L -- "$provided_ld" "$stage/provided/ld.so"
  ld_origin="supplied:$provided_ld_origin"
  if [[ -n "$image_libc" && -n "$image_ld" ]] && same_artifact "$provided_ld" "$image_ld"; then
    mv -- "$image_libc" "$stage/libc.so.6"
    cp -L -- "$provided_ld" "$stage/ld.so"
    image_libc=
    status=ready
    runtime_source=mixed
    pair_status=provided-loader-matches-image
    reason='supplied loader matches image loader; image libc completed the pair'
    libc_origin="image:$image_libc_origin"
    analysis_libc_rel=libc.so.6
    local_libc_rel=libc.so.6
    local_ld_rel=ld.so
  elif [[ -n "$image_libc" && -n "$image_ld" ]]; then
    mkdir -p "$stage/image"
    mv -- "$image_libc" "$stage/image/libc.so.6"
    mv -- "$image_ld" "$stage/image/ld.so"
    image_libc=
    image_ld=
    status=incompatible
    runtime_source=mixed
    pair_status=provided-loader-differs-from-image
    reason='supplied loader differs from image loader; the two pairs were kept separate'
    analysis_libc_rel=image/libc.so.6
    local_libc_rel=image/libc.so.6
    local_ld_rel=image/ld.so
  else
    status=partial
    runtime_source=supplied
    pair_status=loader-only
    reason='supplied loader found but a verified matching libc is unavailable'
  fi
fi

rm -f -- "$stage/.image-libc.so.6" "$stage/.image-ld.so"
if [[ -f "$stage/ld.so" ]]; then
  chmod 755 "$stage/ld.so"
  loader_alias=$(basename -- "${ld_origin#*:}")
  if [[ "$loader_alias" != ld.so && "$loader_alias" =~ ^[A-Za-z0-9._+-]+$ ]]; then
    ln -s ld.so "$stage/$loader_alias"
  fi
fi
[[ ! -f "$stage/libc.so.6" ]] || chmod 644 "$stage/libc.so.6"

write_env() {
  printf '%s=%q\n' "$1" "$2"
}

target_build_id=$([[ -n "$target_path" ]] && elf_build_id "$target_path" || true)

{
  write_env runtime_status "$status"
  write_env runtime_source "$runtime_source"
  write_env pair_status "$pair_status"
  write_env reason "$reason"
  write_env target_path "$target_path"
  write_env target_class "$target_class"
  write_env target_machine "$target_machine"
  write_env target_data "$target_data"
  write_env target_interpreter "$target_interpreter"
  write_env target_build_id "$target_build_id"
  write_env libc_path "$([[ -n "$analysis_libc_rel" ]] && printf '%s/%s' "$output_real" "$analysis_libc_rel" || true)"
  write_env ld_path "$([[ -f "$stage/ld.so" ]] && printf '%s/ld.so' "$output_real" || true)"
  write_env local_libc_path "$([[ -n "$local_libc_rel" ]] && printf '%s/%s' "$output_real" "$local_libc_rel" || true)"
  write_env local_ld_path "$([[ -n "$local_ld_rel" ]] && printf '%s/%s' "$output_real" "$local_ld_rel" || true)"
  write_env libc_origin "$libc_origin"
  write_env ld_origin "$ld_origin"
  write_env libc_build_id "$([[ -n "$analysis_libc_rel" ]] && elf_build_id "$stage/$analysis_libc_rel" || true)"
  write_env ld_build_id "$([[ -n "$local_ld_rel" ]] && elf_build_id "$stage/$local_ld_rel" || true)"
  write_env image_ref "$image"
  write_env image_id "$image_id"
} > "$stage/runtime.env"

if [[ "$preserve_ready" == true && "$status" == unavailable &&
      -f "$output_real/runtime.env" && -f "$output_real/libc.so.6" &&
      -f "$output_real/ld.so" && -n "$target_build_id" &&
      "$(elf_field "$output_real/libc.so.6" 'Machine')" == "$target_machine" &&
      "$(elf_field "$output_real/ld.so" 'Machine')" == "$target_machine" &&
      "$(elf_field "$output_real/libc.so.6" 'Class')" == "$target_class" &&
      "$(elf_field "$output_real/ld.so" 'Class')" == "$target_class" ]]; then
  old_runtime_status=$(sed -n 's/^runtime_status=//p' "$output_real/runtime.env" | sed -n '1p')
  old_target_build_id=$(sed -n 's/^target_build_id=//p' "$output_real/runtime.env" | sed -n '1p')
  if [[ "$old_runtime_status" == ready && "$old_target_build_id" == "$target_build_id" ]]; then
    printf 'runtime_status=ready\n'
    printf 'runtime_source=preserved-existing\n'
    printf 'runtime_pair=preserved-same-target\n'
    exit 0
  fi
fi

old_dir=
if [[ -e "$output_real" || -L "$output_real" ]]; then
  old_dir="$output_parent_real/.pwn-runtime-old.$$"
  [[ ! -e "$old_dir" ]] || { echo "temporary runtime backup already exists: $old_dir" >&2; exit 73; }
  mv -- "$output_real" "$old_dir"
fi
if mv -- "$stage" "$output_real"; then
  stage=
  [[ -z "$old_dir" ]] || rm -rf -- "$old_dir"
else
  [[ -z "$old_dir" ]] || mv -- "$old_dir" "$output_real"
  exit 74
fi

printf 'runtime_status=%s\n' "$status"
printf 'runtime_source=%s\n' "$runtime_source"
printf 'runtime_pair=%s\n' "$pair_status"
if [[ "$status" == ready ]]; then
  printf 'runtime_libc=%s/libc.so.6\n' "$output_real"
  printf 'runtime_ld=%s/ld.so\n' "$output_real"
  exit 0
fi
printf 'runtime_reason=%s\n' "$reason" >&2
exit 2
