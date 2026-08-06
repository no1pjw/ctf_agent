#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 IMAGE COMMAND [ARG ...]" >&2
  exit 64
fi

image=$1
shift

exec docker run --rm --interactive \
  --network none \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --pids-limit 128 \
  --memory 512m \
  --cpus 1 \
  --tmpfs /tmp:rw,noexec,nosuid,size=128m \
  --mount "type=bind,src=${PWD},dst=/work,readonly" \
  --workdir /work \
  "$image" "$@"
