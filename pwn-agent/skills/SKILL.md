---
name: ctf-pwn
description: Solve explicitly authorized CTF pwn challenges from supplied artifacts and an optional exact official endpoint. Covers exploit analysis, local sandbox validation, remote synchronization, and flag acquisition.
---

# CTF Pwn

사용자에게 보이는 진행·오류·결과는 한국어로 쓴다. 명령, 코드, 심볼, 프로토콜 토큰은 정확성을 위해 원문을 유지한다.

## Start lean

1. Read only `work/runtime/runtime.env`, `work/intake-exec.txt`, and non-empty `work/state.json`. Do not preload `HARD_RULES.md`, `role.md`, `playbook.md`, `ruleset.md`, or the full feedback index.
2. Treat the launcher-selected pwn route and recorded CTF scope as fixed. Preserve inputs, calculate no checksums, use no browser/web/search/write-up source, and never execute challenge artifacts on the host.
3. Run one narrow combined probe, choose the cheapest falsifiable hypothesis, and create or edit `work/solve.py` as soon as a primitive is plausible. Open one matching playbook/feedback document only after a concrete blocker identifies the topic.
4. Before a validated flag, never read, create, or modify `work/writeup.md`. A benchmark skips write-up entirely.

## Runtime and execution

- `runtime_status=ready`: use the recorded libc for offsets and the matching loader/libc pair through `pwn-run.sh`; never use host libc, `LD_PRELOAD` alone, or patch the input binary.
- `runtime_status=incompatible`: keep supplied libc calculations separate from the exact image pair. For alignment-sensitive or multi-stage userland exploits, one image-pair structural run is allowed; it does not validate remote offsets.
- `runtime_status=not-applicable`: this is valid when there is no supplied dynamic userland target. Do not mistake a build/container runtime for the challenge target's libc/loader.
- Missing Docker/runtime is non-fatal: continue STATIC-ONLY and use the exact recorded official endpoint only after a parameterized solver is statically cross-checked.
- All target execution goes through the provided Docker/sandbox harness. A generated remote client may contact only `scope/remote-target.env`.

## Fast path

- Combine source, `file`/mitigations, symbols/imports, and the relevant function disassembly into one narrow probe. Do not repeat broad static enumeration.
- Define required gadget semantics first, run `pwn-gadget-index.sh` once, reuse its cache, and stop searching when scarcity is established. Switch to existing calls/dispatch, leaks, ret2dlresolve, or another evidence-backed primitive.
- Prove only reachability -> control/leak -> calculation -> final effect. Prefer the shortest challenge-specific pwntools solver; do not build a generic socket/argument framework.
- Combine syntax check and the next local/remote execution in one command when possible.

## Complex target discipline

- Inspect the actual Docker/runner/service entrypoint in the first combined probe. An invocation, transport, upload, or framing mistake is an environment failure, not an exploit failure and not a reason to restart or enter Deep mode. Correct it once and continue from the same hypothesis.
- Do not infer the vulnerability from the challenge name. Give a name-related theory at most one cheap discriminator; otherwise rank source, version, configuration, and exposed-interface evidence.
- Start with the smallest payload compatible with the proven primitive. If payload size or one upload/framing timeout becomes the blocker, switch immediately to a minimal freestanding form instead of retrying a large generic build.
- Once a strong read/write or control primitive exists, prefer a deterministic object/identity anchor and the shortest direct final effect. Verify permissions, copy-on-write, and alignment once before abandoning a nearly complete path.
- Keep one current strategy plus one evidence-backed fallback. Do not cascade through unrelated final effects without new evidence.

## Local/remote synchronization

- Instrument the solver with secret-free `STAGE=<name>` and bounded `DIAG=<label> len=<n> hex=<max-32-bytes>` output before remote use.
- Every materially new solver that succeeds locally is run remotely immediately. If exact local execution is unavailable, run the first statically cross-checked solver and each materially corrected version. Never replay an unchanged version automatically, brute-force, or flood.
- After failure compare only the last stage, framing, leak/base calculation, runtime provenance, and the failed invariant. Do not restart completed analysis.
- A validated remote `FLAG=<flag>` ends the solve immediately: close the connection, print the flag and acquisition time, then record `verified` in `work/.solved`. Do not delay it for P5, controls, cleanup, or documentation.

## State and escalation

- Keep ordinary Fast work in the active session. Write a checkpoint only after roughly 10 minutes, two failed exploit trials, a probabilistic/multi-stage handoff, or a real interruption risk. In benchmarks, do not checkpoint before the flag.
- Checkpoint only `invariant`, `strategy`, `constraints`, and `next`; never store flags, dumps, or command transcripts in state.
- Escalate in place only for genuinely unresolved source absence, obfuscation, heap/race/probabilistic behavior, environment mismatch, or two evidence-bearing exploit failures. Reuse all passed stages.

Return the primitive chain, exact environment, `work/solve.py`, decisive diagnostics, and the validated flag. Never generalize the exploit to unrelated targets or submit the flag automatically.
