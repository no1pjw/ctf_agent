#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 INPUT_DIR" >&2
  exit 64
fi

input_dir=$(readlink -e -- "$1" 2>/dev/null || true)
[[ -n "$input_dir" && -d "$input_dir" ]] || {
  printf 'input directory not found: %s\n' "$1" >&2
  exit 66
}

dockerfile="$input_dir/Dockerfile"
printf 'intake_root=%s\n' "$input_dir"

mapfile -d '' candidate_files < <(find "$input_dir" -maxdepth 4 -type f -print0 | sort -z)
elf_names=()
for candidate in "${candidate_files[@]}"; do
  if file -b -- "$candidate" 2>/dev/null | grep -qE '^ELF .* executable'; then
    elf_names+=("$(basename -- "$candidate")")
  fi
done
if (( ${#elf_names[@]} > 0 )); then
  printf 'input_elf_names=%s\n' "$(printf '%s\n' "${elf_names[@]}" | sort -u | paste -sd, -)"
else
  printf 'input_elf_names=none\n'
fi

if [[ ! -f "$dockerfile" ]]; then
  echo 'dockerfile=absent'
  echo 'exec_name_check=not-applicable'
  exit 0
fi
echo 'dockerfile=present'

mapfile -t copied_names < <(
  awk '
    toupper($1) == "COPY" || toupper($1) == "ADD" {
      value=$NF
      gsub(/[",\]]/, "", value)
      n=split(value, parts, "/")
      if (parts[n] != "") print parts[n]
    }
  ' "$dockerfile" | sort -u
)
printf 'docker_copy_destinations=%s\n' "$({ printf '%s\n' "${copied_names[@]}"; } | sed '/^$/d' | paste -sd, - || true)"

mapfile -t referenced_names < <(
  {
    grep -Ei '^[[:space:]]*(CMD|ENTRYPOINT)[[:space:]]' "$dockerfile" || true
    while IFS= read -r -d '' script; do
      grep -E '(^[[:space:]]*/(home|app|challenge|ctf)/)|(^|[;[:space:]])(exec|timeout|socat|env|stdbuf)[[:space:]]' "$script" || true
    done < <(find "$input_dir" -maxdepth 4 -type f -name '*.sh' -print0 | sort -z)
  } | grep -Eo '/(home|app|challenge|ctf)(/[A-Za-z0-9._+-]+)+' \
    | sed 's/[;,)]*$//' \
    | awk -F/ 'NF {name=$NF; if (name !~ /\.sh$/) print name}' \
    | sort -u
)
printf 'service_exec_references=%s\n' "$({ printf '%s\n' "${referenced_names[@]}"; } | sed '/^$/d' | paste -sd, - || true)"

mismatches=()
for referenced in "${referenced_names[@]}"; do
  [[ -n "$referenced" ]] || continue
  matched=false
  for known in "${elf_names[@]}" "${copied_names[@]}"; do
    if [[ "$referenced" == "$known" ]]; then
      matched=true
      break
    fi
  done
  [[ "$matched" == true ]] || mismatches+=("$referenced")
done

if (( ${#mismatches[@]} > 0 )); then
  printf 'exec_name_check=warning\n'
  printf 'unmatched_service_executables=%s\n' "$(printf '%s\n' "${mismatches[@]}" | sort -u | paste -sd, -)"
  echo 'intake_warning=Docker/service executable references do not match supplied ELF or COPY destination names; verify the actual service entrypoint before trusting local equivalence.'
else
  echo 'exec_name_check=ok'
fi
