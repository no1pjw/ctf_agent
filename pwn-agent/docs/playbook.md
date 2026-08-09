# Playbook

## Fast Probe

1. Run `pwn-triage.sh` once to collect file type, mitigations, symbols, imports, and `main` disassembly.
2. Prefer supplied source and the exact Dockerfile environment. Reuse `ctf-<challenge>:local`; rebuild only when requested or absent.
3. Reproduce with `pwn-run.sh`, which fixes interactive stdin, runtime network isolation, limits, and timeouts.
4. Build one primitive at a time and attempt at most two candidate exploits before Deep escalation.
5. Avoid GDB until two cheaper tests fail or the exact offset/state remains genuinely ambiguous.

For a multi-stage exploit, create a bounded checkpoint after each primitive: `triage`, `primitive`, `leak`, `arbitrary-read-write`, `control-flow`, `local-flag`, and `remote`. Record only the invariant that passed or failed and the next cheapest discriminator. Keep the latest 20 transitions in `work/state.json`; do not create per-command notes. A resumed run starts by reading this state and matching feedback topics, then retests only the failed stage and its direct prerequisite.

When an official remote endpoint is recorded, switch to Fast-to-Remote as soon as one local exploit run derives a valid local flag. Run the remote solver before a second local success, negative control, P5, detailed evidence work, or write-up. A verified remote flag is the contest completion signal; perform only minimal private evidence saving and cleanup afterward. If the first remote attempt fails, return to the cheapest environment/protocol discriminator and permit one corrected retry.

Before the first remote attempt, retain one capped local-success transcript and the exact libc/runtime provenance. On remote failure, checkpoint the last prompt or invariant reached, keep diagnostic output enabled in the private transcript, and compare only framing, runtime offsets, and the failed invariant. Do not restart static analysis or rewrite an already passed primitive.

For a supplied Dockerfile, treat containers and the generated `ctf-<challenge>:local` image as run-scoped resources. The launcher invokes `pwn-cleanup.sh` after Codex exits, including failures and interruptions. Do not call broad prune commands or remove base images. Use `--keep-docker` only when the user explicitly needs post-run debugging.

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

Escalate for source absence, stripped/obfuscated binaries, heap/race/probabilistic behavior, environment mismatch, unresolved protocol/libc, two failed exploit trials, or budget exhaustion. Reuse Fast results. Without a remote endpoint, P4 executes two clean successes and one negative control; with one, Fast-to-Remote takes precedence and those controls are deferred until remote failure. P5 verifies only the existing packet.

## Official remote endpoint

When `scope/remote-target.env` records a user-declared official CTF endpoint:

1. Complete local primitive and solver validation before target traffic.
2. Parameterize `work/solve.py` with pwntools `REMOTE HOST=<host> PORT=<port>`; never hard-code a second endpoint. Exit nonzero when no valid flag is obtained so the bounded harness can distinguish failure.
3. Run only through `pwn-remote-run.sh`, with one immediate attempt by default and a second only after a bounded protocol/environment correction. Measure from remote solver start until the first validated `FLAG=` line with the harness monotonic timer.
4. Do not scan ports, discover adjacent hosts, brute-force ASLR or credentials, persist a shell, pivot, or contact a scoreboard.
5. Require `solve.py` to return the validated flag and print exactly `FLAG=<flag>` on stdout; never print that marker for an unvalidated candidate.
6. Stop immediately after the minimum flag proof. Show `획득한 플래그: <flag>` and `원격 플래그 획득 시간: N.NNN초` immediately in the terminal and include both in the final user response. Save transcript and candidate flag under `evidence/private/`, while redacting it from `work/writeup.md`.
