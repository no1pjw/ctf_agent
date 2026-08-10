#!/usr/bin/env python3
import os
import re
import sys
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
runtime_status = os.environ.get("CTF_PWN_RUNTIME_STATUS", "unavailable")
local_libc_path = Path(
    args.LOCAL_LIBC or os.environ.get("CTF_PWN_LOCAL_LIBC_PATH", runtime_dir / "libc.so.6")
).resolve()
local_ld_path = Path(
    args.LOCAL_LD or os.environ.get("CTF_PWN_LOCAL_LD_PATH", runtime_dir / "ld.so")
).resolve()

context.binary = ELF(str(binary_path), checksec=False)
context.log_level = args.LOG or "info"
libc = ELF(str(libc_path), checksec=False) if libc_path.is_file() else None
local_libc = ELF(str(local_libc_path), checksec=False) if local_libc_path.is_file() else None


def active_libc():
    """Use the supplied analysis libc remotely and the exact image libc locally."""
    return libc if args.REMOTE else (local_libc or libc)


def stage(name, **fields):
    """Emit a secret-free stage marker to the private local/remote transcript."""
    slug = re.sub(r"[^a-z0-9._-]+", "-", str(name).lower()).strip("-") or "unknown"
    safe = []
    for key, value in fields.items():
        key = re.sub(r"[^a-z0-9._-]+", "-", str(key).lower()).strip("-")
        value = str(value).replace("\r", " ").replace("\n", " ")[:120]
        safe.append(f"{key}={value}")
    suffix = " " + " ".join(safe) if safe else ""
    print(f"STAGE={slug}{suffix}", file=sys.stderr, flush=True)


def fail_stage(name, reason):
    stage(name, status="failed", reason=reason)


def diag_bytes(label, data, limit=32):
    """Record bounded raw framing evidence without dumping an unlimited stream."""
    raw = bytes(data)
    print(
        f"DIAG={label} len={len(raw)} hex={raw[:limit].hex()}",
        file=sys.stderr,
        flush=True,
    )


def sandbox_argv():
    """Run the target only through the Docker harness with the exact runtime pair."""
    have_libc = libc_path.is_file()
    have_ld = ld_path.is_file()
    if runtime_status == "ready":
        if not (have_libc and have_ld):
            raise SystemExit("runtime bundle is incomplete; refusing a mixed/system fallback")
        runtime_args = ["--runtime-dir", str(runtime_dir)]
    elif local_libc_path.is_file() and local_ld_path.is_file():
        runtime_args = ["--structural-runtime-dir", str(runtime_dir)]
    else:
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
        *runtime_args,
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
    # Use active_libc() for calculations and stage()/diag_bytes() before each transition.
    raise NotImplementedError("implement challenge-specific exploit")


if __name__ == "__main__":
    stage(
        "runtime-profile",
        mode="remote" if args.REMOTE else "local",
        status=runtime_status,
        libc=active_libc().path if active_libc() is not None else "unavailable",
        loader=str(ld_path if runtime_status == "ready" else local_ld_path),
    )
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
