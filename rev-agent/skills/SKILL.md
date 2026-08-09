---
name: ctf-rev
description: Analyze and solve explicitly authorized CTF reverse-engineering challenges involving native binaries, managed bytecode, virtual machines, packers, or obfuscation. Use for static and sandboxed dynamic analysis, algorithm recovery, constraint extraction, deobfuscation, and reproducible flag derivation.
---

# CTF Reverse Engineering

Read `../docs/HARD_RULES.md`, then `../docs/role.md` and `../docs/playbook.md`. Read the active challenge ledger and `../../rules/ruleset.md` before touching artifacts.

1. Preserve originals and work on copies without calculating checksums.
2. Start with a bounded Fast Probe; read only `../feedback/index.md` initially and open a linked feedback file only when its symptoms match. Rank at most three hypotheses by cheapest falsifying test.
3. Identify only the format, runtime, imports, sections, strings, and behavior needed for those tests; escalate in place on packing, obfuscation, environment mismatch, repeated failure, or budget exhaustion.
4. Use static analysis first; perform dynamic analysis only in `../../sandbox/`.
5. Write small extraction or emulation scripts when manual steps would be error-prone.
6. Verify recovered inputs with the program or an independent reimplementation.
7. In Fast mode write only the recovery script and concise write-up. Update feedback or detailed notes only after escalation, at a long-running checkpoint, or for a durable new lesson.
8. When invoked by `ctf-rev`, keep the launcher-selected mode and runtime boundary. Write `verified` to `work/.solved` only after independent derivation or sandboxed target verification; this enables deletion of only recoverable duplicate inputs while preserving the recovery script, write-up, scope, private evidence, and feedback.

Return observations, function/data map, commands, scripts, candidate output, negative controls, and reproduction steps.
