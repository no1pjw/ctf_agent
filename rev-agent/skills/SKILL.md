---
name: ctf-rev
description: Solve explicitly authorized local CTF reverse-engineering challenges from supplied native binaries, managed bytecode, virtual machines, packers, scripts, firmware, or obfuscated programs. Use for static mapping, sandboxed dynamic analysis, algorithm and constraint recovery, deobfuscation, minimal recovery scripting, and verified flag derivation.
---

# CTF Reverse Engineering

사용자에게 보이는 진행·오류·결과는 한국어로 쓴다. 명령, 코드, 심볼과 flag는 원문을 유지한다.

The objective is minimum time to a verified flag. Treat each supplied artifact as an answer-extraction target, not a whole-program-understanding assignment.

## Fast contract

1. The launcher-selected paths are authoritative. Read `$CTF_REV_WORK_DIR/intake-exec.txt` when that variable is set; otherwise use the exact intake path in the prompt. Never search the workspace for it and never reopen this `SKILL.md` with a tool.
2. Preserve the input; calculate no checksums; use no browser, web search, GitHub search, write-up, or subagent. Do not preload policy, role/playbook, or the feedback index.
3. Run `"$CTF_REV_FAST_PROBE" "$CTF_REV_INPUT_DIR"` once when the launcher provides it. Otherwise use one equivalent bounded probe for format/runtime, concise symbols/imports, flag-shaped strings/resources, success/failure references, and the nearest validator or decoder. Keep output under 16 KiB.
4. Test at most two direct flag hypotheses. Prefer an embedded constant/resource, compact decoder, one validator inversion, or bounded constraint model.
5. Open one matching feedback or playbook file only after a concrete blocker identifies the topic.

Do not spend a separate turn narrating a hypothesis when the next bounded test is obvious. Run that test directly; reserve user-visible text for a real blocker or the verified flag.

## Direct-path rules

- Analyze only functions and data on the shortest suspected flag path. Do not enumerate all functions, build a complete CFG/call graph, or broadly decompile.
- Never dump or disassemble an entire large raw blob or section. First recover referenced offsets, then inspect bounded windows with `xxd -s/-l`, `dd`, or an address-limited disassembly.
- Once a transformation is clear, extract its constants and run the smallest inverse immediately. Do not add another descriptive analysis turn first.
- A recorded flag format such as `XMAS{...}` may be a submission wrapper rather than bytes accepted by the program. If a verified payload lacks the wrapper, construct and test `PREFIX{payload}` before rejecting the recovery equation.
- Make `work/recover.py` the smallest reproducible extractor. Do not build a general emulator or framework when a direct command or short script is sufficient.

## Execution boundary

- Never execute challenge artifacts on the host, even with `danger-full-access`.
- Static tools such as `file`, `readelf`, `objdump`, `nm`, `strings`, archive listing, and parsers may inspect inputs without executing them.
- Dynamic analysis is allowed only through `$CTF_REV_RUNNER --input-dir "$CTF_REV_INPUT_DIR" "$CTF_REV_IMAGE" <COMMAND>`. Inputs appear read-only at `/ctf-input`. Use an explicit bounded command; never invoke a bare image or enable network access.
- If Dockerfile/image preparation fails, continue STATIC-ONLY. Do not create an ad-hoc online environment, download a runtime, or substitute an unrelated host runtime.
- Treat decompiler output as a hypothesis. Confirm decisive branches, widths, signedness, table indexes, and constants against disassembly or an independent implementation.

## Fast path

- Native: identify input, transform/compare, success output, and anti-analysis checks; inspect only the functions and data referenced by that path.
- Managed/bytecode: identify the exact runtime and entry method, then recover constants/opcodes without setting up a broad framework.
- VM/obfuscation: recover dispatcher state, opcode semantics, state transition, and exit predicate incrementally; emulate only the slice required for the flag.
- Packers: prove unpacking is necessary before spending time on it. Prefer a sandboxed memory dump or deterministic loader reconstruction over manual cleanup.
- Constraints: simplify first, bound the domain, and use a solver only when cheaper algebraic inversion is disproved. Never launch unbounded brute force.
- Combine recovery-script creation, syntax checking, decisive verification, and `.solved` recording into the fewest tool turns possible.

## Verification and completion

- Verify a candidate with the cheapest decisive method: one independent reconstruction or one bounded positive run inside the supplied Docker image. Add a negative control only when acceptance remains ambiguous.
- A flag-looking string embedded in data is only a candidate until its derivation or success path is verified. Format wrapping alone is not a failed recovery hypothesis.
- Print `FLAG=<value>` immediately after verification, then write the exact word `verified` to `work/.solved`.
- After printing a verified flag, make no more tool calls and do not delay completion for write-up, cleanup, feedback, or a broader function map. `ctf-learn` handles durable lessons later.

## State and escalation

- Keep Fast work in the active session. Create a minimal `work/state.json` checkpoint only after roughly 10 minutes, two evidence-bearing recovery failures, a long-running bounded job, or real interruption risk.
- Store only the current invariant, strategy, constraints, failed discriminator, and next test. Do not store flags, dumps, or command transcripts in state.
- Escalate in place for stripped/source-absent targets, packing, obfuscation, anti-debugging, unknown VM/bytecode, environment mismatch, two failed direct recovery attempts, or budget exhaustion. Deep mode remains flag-directed and does not authorize whole-program analysis by default. Reuse every passed stage.

Return the shortest recovery chain, `work/recover.py`, decisive verification, and the verified flag.
