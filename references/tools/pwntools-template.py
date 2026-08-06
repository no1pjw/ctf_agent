#!/usr/bin/env python3
from pwn import *

context.binary = ELF(args.BIN or "./chall", checksec=False)
context.log_level = args.LOG or "info"


def start():
    if args.REMOTE:
        if not args.HOST or not args.PORT:
            raise SystemExit("REMOTE requires HOST and PORT")
        return remote(args.HOST, int(args.PORT), timeout=5)
    if args.GDB:
        return gdb.debug([context.binary.path], gdbscript="continue")
    return process([context.binary.path])


def solve(io):
    # Build and verify one exploit primitive at a time.
    raise NotImplementedError("implement challenge-specific exploit")


if __name__ == "__main__":
    tube = start()
    try:
        solve(tube)
    finally:
        tube.close()
