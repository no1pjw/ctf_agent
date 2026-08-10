#!/usr/bin/env python3
import os
from pathlib import Path

from pwn import *

binary_path = Path(args.BIN or os.environ.get("CTF_PWN_BINARY_PATH", "./chall")).resolve()
runtime_dir = Path(
    args.RUNTIME
    or os.environ.get("CTF_PWN_RUNTIME_DIR", Path(__file__).resolve().parent / "runtime")
).resolve()
libc_path = Path(
    args.LIBC or os.environ.get("CTF_PWN_LIBC_PATH", runtime_dir / "libc.so.6")
).resolve()
ld_path = Path(args.LD or os.environ.get("CTF_PWN_LD_PATH", runtime_dir / "ld.so")).resolve()
runner_path = Path(
    args.RUNNER
    or os.environ.get(
        "CTF_PWN_RUNNER",
        Path(os.environ.get("CTF_AGENT_ROOT", Path(__file__).resolve().parents[2]))
        / "references"
        / "tools"
        / "pwn-run.sh",
    )
).resolve()
image_ref = args.IMAGE or os.environ.get("CTF_PWN_IMAGE", "")

context.binary = ELF(str(binary_path), checksec=False)
context.log_level = args.LOG or "info"
libc = ELF(str(libc_path), checksec=False) if libc_path.is_file() else None


def sandbox_argv():
    """Run the target only through the Docker harness with the exact runtime pair."""
    have_libc = libc_path.is_file()
    have_ld = ld_path.is_file()
    if have_libc != have_ld:
        raise SystemExit("runtime bundle is incomplete; refusing a mixed/system fallback")
    if not have_libc:
        raise SystemExit(
            "exact runtime bundle unavailable; use pwn-run.sh in the challenge image "
            "or run the parameterized REMOTE branch"
        )
    if not runner_path.is_file():
        raise SystemExit(f"pwn sandbox runner not found: {runner_path}")
    if not image_ref:
        raise SystemExit("local execution requires IMAGE=<exact challenge image>")
    return [
        str(runner_path),
        "--runtime-dir",
        str(runtime_dir),
        "--binary",
        str(binary_path),
        image_ref,
    ]


def start():
    if args.REMOTE:
        if not args.HOST or not args.PORT:
            raise SystemExit("REMOTE requires HOST and PORT")
        return remote(args.HOST, int(args.PORT), timeout=5)
    if args.GDB:
        raise SystemExit("GDB must be invoked by P4 inside the challenge container")
    return process(sandbox_argv())


def solve(io):
    # Build and verify one exploit primitive at a time.
    raise NotImplementedError("implement challenge-specific exploit")


if __name__ == "__main__":
    tube = start()
    try:
        flag = solve(tube)
        if flag is None:
            raise SystemExit("exploit completed without a validated flag")
        if isinstance(flag, bytes):
            flag = flag.decode(errors="strict")
        if not isinstance(flag, str) or not flag:
            raise SystemExit("solve() must return a validated flag string or bytes")
        print(f"FLAG={flag}", flush=True)
    finally:
        tube.close()
