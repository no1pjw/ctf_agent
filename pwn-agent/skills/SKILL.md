---
name: ctf-pwn
description: Analyze and solve explicitly authorized CTF pwn challenges involving binaries, memory corruption, sandbox escapes inside challenge containers, or exploitation primitives. Use for mitigation analysis, crash triage, exploit construction, local/remote parameterization, debugger validation, and reproducible flag derivation.
---

# CTF Pwn

사용자에게 보이는 진행 상황, 판단, 오류 설명 및 최종 답변은 기본적으로 한국어로 작성한다. 명령어, 코드, 경로, 심볼 및 원문 진단 메시지는 정확성을 위해 원래 표기를 유지한다.

Read `../docs/HARD_RULES.md`, then `../docs/role.md` and `../docs/playbook.md`. Read the active challenge ledger and `../../rules/ruleset.md`.

1. Preserve inputs without calculating checksums; complete P0-Lite and treat category routing as fixed when invoked by `ctf-pwn`.
2. Start with the bounded Fast Probe in `../docs/playbook.md`; read only `../feedback/index.md` initially and open a linked feedback file only when its symptoms match. Escalate in place only on explicit triggers.
3. Use `../../references/tools/pwn-triage.sh`, `pwn-build.sh`, `pwn-run.sh`, and the pwntools template instead of rebuilding command logic.
   If neither a Dockerfile nor the named cached image exists, enter `STATIC-ONLY`: run static triage once, do not synthesize or pull an environment, do not retry Docker, and do not escalate solely for the missing Dockerfile.
4. Prove primitives incrementally: reachability, control, leak, calculation, final effect.
5. Execute only through P4 inside Docker/sandbox or the exact official endpoint recorded in `scope/remote-target.env`. For a recorded remote target, finish and locally validate the solver first, keep it compatible with pwntools `REMOTE HOST=... PORT=...`, then use `../../references/tools/pwn-remote-run.sh` for no more than two bounded attempts.
6. Have P4 produce two clean successes plus one negative control for deterministic solves. Have P5 verify existing evidence without executing.
7. In Fast mode write only `work/solve.py` and concise `work/writeup.md`; use detailed logs only for Deep/Audit or checkpoints.

Return the primitive chain, exploit, environment, transcripts, controls, and reproduction steps. Make `solve.py` print `FLAG=<validated flag>` only after format and derivation validation. When a remote run obtains it, immediately show `획득한 플래그: <validated flag>` in the user-visible terminal and repeat the exact flag in the final answer; never replace it with only a file path. Store remote transcripts and candidate flags under `evidence/private/`, but do not put flag plaintext in the public write-up or submit it to a scoreboard. Never generalize an exploit to unrelated targets.
