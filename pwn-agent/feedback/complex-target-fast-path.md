# Complex target fast path

Use this only after the observed blocker involves a layered runner, large payload transfer, or a strong primitive with an uncertain final effect.

## Symptoms

- Static analysis is progressing, but repeated runner/service invocation corrections consume exploit trials.
- A generic or static-runtime payload is slow or unreliable to transfer.
- A strong read/write primitive exists, but the solve rotates through unrelated final effects.
- Challenge naming is driving hypotheses more strongly than source, version, configuration, or interface evidence.

## Durable response

1. Record the exact runner and service entrypoint once. Treat wrapper, transport, and framing errors as environment failures, not exploit failures.
2. Use one cheap test for a name-derived hypothesis, then move to evidence-ranked candidates.
3. Prefer the smallest freestanding payload compatible with the primitive; after one size/framing failure, stop retrying the large form.
4. Prefer a deterministic identity/object anchor and direct final effect. Check permission state, copy-on-write, and alignment once before switching.
5. Keep one active strategy and one evidence-backed fallback. A new fallback requires new evidence, not elapsed time alone.

This feedback contains no challenge-specific addresses, flags, or endpoint data.
