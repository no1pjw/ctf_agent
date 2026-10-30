#!/usr/bin/env bash
set -euo pipefail

image=
if [[ "${1:-}" == "--image" ]]; then
  image=${2:-}
  shift 2
fi
if [[ $# -ne 0 ]]; then
  printf 'usage: %s [--image IMAGE]\n' "$0" >&2
  exit 64
fi

command -v docker >/dev/null 2>&1 || { echo 'docker=missing'; exit 1; }
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
"$script_dir/ctf-docker-ready.sh" || { echo 'docker_daemon=unavailable'; exit 1; }
echo 'docker_daemon=ok'

if command -v gdb >/dev/null 2>&1; then
  printf 'gdb=%s\n' "$(gdb --version | sed -n '1p')"
else
  echo 'gdb=missing'
fi

if [[ -n "$image" ]]; then
  timeout --kill-after=2s 15s docker image inspect "$image" >/dev/null 2>&1 || {
    printf 'image=missing:%s\n' "$image"
    exit 2
  }

  probe="$(printf 'ctf-stdin-ok' | docker run --rm -i --network none --entrypoint /bin/cat "$image")"
  [[ "$probe" == 'ctf-stdin-ok' ]] || { echo 'docker_stdin=failed'; exit 3; }
  printf 'image=ok:%s\n' "$image"
  echo 'docker_stdin=ok'
fi
