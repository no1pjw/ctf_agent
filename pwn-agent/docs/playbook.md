# Playbook

## Fast Probe

1. Run `pwn-triage.sh` once to collect file type, mitigations, symbols, imports, and `main` disassembly.
2. Prefer supplied source and the exact Dockerfile environment. Reuse `ctf-<challenge>:local`; rebuild only when requested or absent.
3. Reproduce with `pwn-run.sh`, which fixes interactive stdin, runtime network isolation, limits, and timeouts.
4. Build one primitive at a time and attempt at most two candidate exploits before Deep escalation.
5. Avoid GDB until two cheaper tests fail or the exact offset/state remains genuinely ambiguous.

## No Dockerfile

If no Dockerfile and no matching cached image exist:

1. Mark the runtime `STATIC-ONLY` and continue immediately with source, `file`, mitigations, symbols, imports, strings, and disassembly.
2. Do not create an ad-hoc Dockerfile, pull a generic image, retry Docker, or execute the binary on the host.
3. Do not escalate merely because the Dockerfile is absent. Escalate only for ordinary technical triggers found during analysis.
4. When a decisive dynamic test is unavoidable, finish the static map first and report the exact required architecture, loader, libc, service command, or other missing runtime component.

## Malformed variadic input

When a scanf/printf-family format has more conversions than supplied pointers/arguments:

1. Record the undefined behavior without trying to prove portability across unrelated libc versions.
2. Prioritize the supplied Docker image and libc.
3. Test a bounded matrix: delimiter, newline, EOF, and socket/process half-close.
4. Prefer ending input immediately after the final required conversion when EOF can prevent an unmatched trailing conversion.
5. Encode the successful framing explicitly in `solve.py` with timeouts.

## Escalation and verification

Escalate for source absence, stripped/obfuscated binaries, heap/race/probabilistic behavior, environment mismatch, unresolved protocol/libc, two failed exploit trials, or budget exhaustion. Reuse Fast results. P4 executes two clean successes and one negative control; P5 verifies only that packet.
