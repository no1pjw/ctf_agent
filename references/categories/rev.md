# Reverse engineering reference

## Triage

- Identify container, architecture, ABI, runtime, entry point, imports, sections, entropy, and debug data.
- Search for input, comparisons, crypto constants, dispatch loops, error/success strings, and serialization.

## Strategy

- Native: map input-to-check path and data dependencies.
- Bytecode/VM: recover instruction format, state, dispatcher, and semantics; write an emulator.
- Packed/loader: identify unpack boundary and dump only inside the sandbox.
- Obfuscated: recover invariants, state transitions, and opaque-predicate dependencies before simplification.

## Verification

Reimplement the recovered transformation, verify a known path, reject at least one negative input, and compare with a clean target run.
