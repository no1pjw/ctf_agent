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
