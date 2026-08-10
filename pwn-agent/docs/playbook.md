# Playbook

## Runtime bundle first

Before the Fast Probe, read `work/runtime/runtime.env`. The launcher prepares it in this order: a complete supplied libc/loader pair; a supplied component completed only after it matches the exact challenge image counterpart; or a libc/loader pair extracted together from that image. It never downloads a generic runtime, patches an input binary, or silently substitutes the host libc.

Use `libc_path` for remote libc symbols and offsets whenever it is present. For local reproduction, require `runtime_status=ready` and invoke `pwn-run.sh --runtime-dir work/runtime --binary <target> <image>` so `ld.so --library-path /ctf-runtime` and `libc.so.6` are applied together inside the sandbox. Do not run the target directly with `LD_PRELOAD` or patch its interpreter. If the bundle is `partial`, `ambiguous`, or `incompatible`, keep its provenance for diagnosis but do not call it an exact local runtime; continue STATIC-ONLY and the bounded official remote path when otherwise ready.

## Fast Probe

1. Run `pwn-triage.sh` once to collect file type, mitigations, symbols, imports, and `main` disassembly.
2. Prefer supplied source and the exact Dockerfile environment. Reuse `ctf-<challenge>:local`; rebuild only when requested or absent.
3. Reproduce with `pwn-run.sh`, using its prepared runtime-bundle mode when `runtime_status=ready`; it fixes interactive stdin, explicit loader/libc selection, runtime network isolation, limits, and timeouts.
4. Build one primitive at a time and attempt at most two candidate exploits before Deep escalation.
5. Avoid GDB until two cheaper tests fail or the exact offset/state remains genuinely ambiguous.

## Bounded gadget discovery

Do not use gadget enumeration as an open-ended exploration loop.

1. Write down the exact semantics required by the current chain before searching: pivot, argument setup, indirect dispatch, syscall, or stack adjustment.
2. Run `../../references/tools/pwn-gadget-index.sh <main-elf> work/cache` once. Its 60-second cap and Build-ID cache are the gadget budget for the main ELF. A cache hit replaces a new search.
3. If `leave ; ret` plus `pop rbp ; ret` establishes a stack pivot, mark the pivot primitive passed. Do not keep searching for alternate pivots without evidence that this one is unusable.
4. If the same index lacks required classic register-pop gadgets, record `gadget-scarcity=confirmed` and stop broad searches of the main ELF. Move immediately to existing PLT/GOT calls, function-internal or indirect dispatch sequences, leak/base calculation, ret2dlresolve feasibility, or another narrowly justified strategy.
5. Permit at most one additional targeted disassembly/opcode query, only for a named semantic that the compact index cannot express. Do not install or rotate through additional gadget tools merely to repeat the same enumeration.
6. Do not enumerate the supplied libc until the exploit has a concrete libc leak/base strategy. Once it does, search only the required libc semantics, cache the selected offsets, and never substitute offsets from the Docker image libc when the runtime manifest says the supplied and image pairs differ.
7. Store only the compact Build-ID index and selected offsets. Full gadget dumps are disposable caches and are not learning records.

CET metadata is a one-time runtime question, not a reason to repeat gadget discovery. Record whether IBT/SHSTK is actually enforced in the exact sandbox when that changes exploit viability; otherwise continue from the established primitive.

For a multi-stage exploit, create a bounded checkpoint after each primitive: `triage`, `primitive`, `leak`, `arbitrary-read-write`, `control-flow`, `local-flag`, and `remote`. Record only the invariant that passed or failed and the next cheapest discriminator. Keep the latest 20 transitions in `work/state.json`; do not create per-command notes. A resumed run starts by reading this state and matching feedback topics, then retests only the failed stage and its direct prerequisite.

When an official remote endpoint is recorded, switch to Fast-to-Remote as soon as the solver is ready. If an exact local runtime exists, one local exploit-derived flag is enough. If no local runtime exists, statically cross-check the primitive, offsets, addresses, and I/O framing, syntax-check the parameterized solver, and make the first bounded remote attempt without waiting for a Dockerfile, cached image, or local flag. Run it before a negative control, P5, detailed evidence work, or write-up. A verified remote flag is the contest completion signal; perform only minimal private evidence saving and cleanup afterward. If the first remote attempt fails, return to the cheapest environment/protocol discriminator and permit one corrected retry.

Before the first remote attempt, retain one capped local-success transcript and exact runtime provenance when a local runtime exists. In `STATIC-ONLY`, retain the compact static cross-check instead. On remote failure, checkpoint the last prompt or invariant reached, keep diagnostic output enabled in the private transcript, and compare only framing, runtime offsets, and the failed invariant. Do not restart static analysis or rewrite an already passed primitive.

When local succeeds but remote fails, inspect `runtime.env` before changing the exploit primitive: confirm which libc supplied the symbol offsets, whether the local loader/libc pair was exact, and whether the leak-to-base calculation assumed the same ABI. The loader reproduces local process startup; it is never sent to or executed on the remote service.

For a supplied Dockerfile, treat containers and the generated `ctf-<challenge>:local` image as run-scoped resources. The launcher invokes `pwn-cleanup.sh` after Codex exits, including failures and interruptions. Do not call broad prune commands or remove base images. Use `--keep-docker` only when the user explicitly needs post-run debugging.

## No Dockerfile

If no Dockerfile and no matching cached image exist:

1. Mark the runtime `STATIC-ONLY` and continue immediately with source, `file`, mitigations, symbols, imports, strings, and disassembly.
2. Do not create an ad-hoc Dockerfile, pull a generic image, retry Docker, or execute the binary on the host.
3. Do not escalate merely because the Dockerfile is absent. Escalate only for ordinary technical triggers found during analysis.
4. If an exact official endpoint is recorded and static analysis is sufficient to complete a parameterized solver, use the bounded remote harness immediately; the missing local runtime is not a blocker. Otherwise, when a decisive dynamic test is unavoidable, finish the static map first and report the exact required architecture, loader, libc, service command, or other missing runtime component.

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

1. Complete local primitive and solver validation when an exact local runtime exists. Without one, independently cross-check the static exploit chain and syntax-check the solver; do not treat the absent runtime as a prerequisite for the first bounded target attempt.
2. Parameterize `work/solve.py` with pwntools `REMOTE HOST=<host> PORT=<port>`; never hard-code a second endpoint. Exit nonzero when no valid flag is obtained so the bounded harness can distinguish failure.
3. Run only through `pwn-remote-run.sh`, with one immediate attempt by default and a second only after a bounded protocol/environment correction. Measure from remote solver start until the first validated `FLAG=` line with the harness monotonic timer.
4. Do not scan ports, discover adjacent hosts, brute-force ASLR or credentials, persist a shell, pivot, or contact a scoreboard.
5. Require `solve.py` to return the validated flag and print exactly `FLAG=<flag>` on stdout; never print that marker for an unvalidated candidate.
6. Stop immediately after the minimum flag proof. Show `획득한 플래그: <flag>` and `원격 플래그 획득 시간: N.NNN초` immediately in the terminal and include both in the final user response. Save transcript and candidate flag under `evidence/private/`, while redacting it from `work/writeup.md`.
