#!/usr/bin/env bash
set -euo pipefail

input_dir=${CTF_REV_INPUT_DIR:-}
entrypoint=
timeout_seconds=30
kill_after_seconds=${CTF_REV_KILL_AFTER_SECONDS:-2}
output_file=
docker_bin=${CTF_DOCKER_BIN:-docker}

usage() {
  cat <<'EOF'
usage: rev-run.sh --input-dir DIR [--entrypoint PATH] [--timeout SEC] [--output FILE] IMAGE COMMAND [ARG ...]

Mounts DIR read-only at /ctf-input and runs one explicit bounded command in a
network-disabled disposable container. Bare IMAGE execution is rejected.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input-dir) input_dir=${2:-}; shift 2 ;;
    --entrypoint) entrypoint=${2:-}; shift 2 ;;
    --timeout) timeout_seconds=${2:-}; shift 2 ;;
    --output) output_file=${2:-}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    --*) printf 'unknown option: %s\n' "$1" >&2; exit 64 ;;
    *) break ;;
  esac
done

[[ -n "$input_dir" && -d "$input_dir" ]] || { echo '--input-dir DIR is required' >&2; exit 64; }
[[ $# -ge 2 ]] || { echo 'IMAGE and an explicit COMMAND are required' >&2; usage >&2; exit 64; }
[[ "$timeout_seconds" =~ ^[0-9]+$ ]] && (( timeout_seconds >= 1 && timeout_seconds <= 900 )) || {
  echo '--timeout must be 1..900 seconds' >&2
  exit 65
}
[[ "$kill_after_seconds" =~ ^[0-9]+$ ]] && (( kill_after_seconds >= 1 && kill_after_seconds <= 30 )) || {
  echo 'CTF_REV_KILL_AFTER_SECONDS must be 1..30 seconds' >&2
  exit 65
}
input_dir=$(readlink -e -- "$input_dir")
image=$1
shift

timeout --kill-after="${kill_after_seconds}s" 10 "$docker_bin" image inspect "$image" >/dev/null 2>&1 || {
  printf 'image unavailable or Docker inspect timed out: %s\n' "$image" >&2
  exit 66
}

run_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/ctf-rev-run.XXXXXX")
cid_file="$run_tmp_dir/container.cid"
cleanup_owned_container() {
  local cid=
  if [[ -s "$cid_file" ]]; then
    IFS= read -r cid < "$cid_file" || true
    if [[ "$cid" =~ ^[0-9a-f]{12,64}$ ]]; then
      timeout --kill-after="${kill_after_seconds}s" 5 "$docker_bin" rm --force "$cid" >/dev/null 2>&1 || true
    fi
  fi
  rm -f -- "$cid_file"
  rmdir -- "$run_tmp_dir" 2>/dev/null || true
}
trap cleanup_owned_container EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

docker_args=(
  run --rm --interactive
  --cidfile "$cid_file"
  --network none
  --read-only
  --cap-drop ALL
  --security-opt no-new-privileges
  --pids-limit 128
  --memory 768m
  --cpus 1
  --tmpfs /tmp:rw,nosuid,size=192m
  --mount "type=bind,src=$input_dir,dst=/ctf-input,readonly"
  --workdir /ctf-input
)
[[ -z "$entrypoint" ]] || docker_args+=(--entrypoint "$entrypoint")
if [[ -n ${CTF_BENCH_RUN_ID:-} ]]; then
  [[ "$CTF_BENCH_RUN_ID" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo 'invalid CTF_BENCH_RUN_ID' >&2; exit 65; }
  docker_args+=(--label "ctf.bench.run=$CTF_BENCH_RUN_ID")
fi
if [[ -n ${CTF_BENCH_VARIANT:-} ]]; then
  [[ "$CTF_BENCH_VARIANT" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo 'invalid CTF_BENCH_VARIANT' >&2; exit 65; }
  docker_args+=(--label "ctf.bench.variant=$CTF_BENCH_VARIANT")
fi
docker_args+=("$image" "$@")

if [[ -n "$output_file" ]]; then
  mkdir -p "$(dirname -- "$output_file")"
  set +e
  timeout --kill-after="${kill_after_seconds}s" "$timeout_seconds" \
    "$docker_bin" "${docker_args[@]}" 2>&1 | tee "$output_file"
  status=${PIPESTATUS[0]}
  set -e
else
  set +e
  timeout --kill-after="${kill_after_seconds}s" "$timeout_seconds" \
    "$docker_bin" "${docker_args[@]}"
  status=$?
  set -e
fi
if [[ $status -eq 124 || $status -eq 137 ]]; then
  printf 'rev_run_timeout=%ss; owned container cleanup requested\n' "$timeout_seconds" >&2
fi
exit "$status"
