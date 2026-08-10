# Pwn reference

## Triage

Record architecture, endianness, PIE, NX, RELRO, canary, CET, libc/loader, seccomp, protocol, and restart behavior.

## Primitive ladder

1. Controlled input reaches target code.
2. Demonstrate exact corruption or logic primitive.
3. Establish information disclosure when required.
4. Calculate addresses from runtime evidence.
5. Achieve the minimum challenge-specific final effect.

Keep stages independently testable. Treat offsets, gadgets, and timing assumptions as named parameters.

## Bounded gadget search

Name the exact required semantics before searching. Run `references/tools/pwn-gadget-index.sh <binary> work/cache` once for the main ELF and reuse its Build-ID cache. When a usable pivot is established but the compact index lacks classic register-pop gadgets, record `gadget-scarcity=confirmed` and stop broad binary searches. Switch to PLT/GOT call sites, indirect dispatch, leak/base calculation, ret2dlresolve, or another narrowly justified primitive. Search a supplied libc only after a concrete libc-base strategy exists, and never mix its offsets with a different local image libc.
