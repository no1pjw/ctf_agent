# CTF Agent Orchestrator

## User-facing language

Write every user-visible progress update, decision, error explanation, question, and final answer in Korean by default. Preserve commands, code, paths, symbols, flags, protocol tokens, and verbatim diagnostic text in their original form when translation could reduce accuracy.

## Learning mode

When `$ctf-learn` is invoked, do not enter the P0-P6 solve pipeline. Read `learn-agent/skills/ctf-learn/SKILL.md`, review only the completed challenge artifacts needed to extract lessons, and modify only the feedback directory named in the prompt. Do not execute challenge artifacts, contact a target, change core skills/policies/tools, or store challenge-specific answers.

Operate only on CTF challenges, local labs, and systems for which the user has explicit authorization. Treat every supplied host as out of scope until its CTF context and allowed target are recorded in the challenge ledger.

## Startup

1. Read `rules/ruleset.md`, `state/notes.md`, and `state/todo.md`.
2. Create or select `challenges/<challenge-id>/` and record source, category, scope, flag format, artifacts, and network allowance.
3. Never execute an untrusted artifact outside `sandbox/`. Prefer offline inspection first.
4. Route work through the phase owners below. A phase may be repeated when evidence changes.

Adaptive mode is the default for every category: P0-Lite, fixed routing when the launcher already knows the category, a bounded specialist Fast Probe, P5-Lite, and automatic in-place escalation to the full P0-P6 workflow only when a defined trigger fires. For local pwnable intake, `ctf-pwn <challenge-name>` implements this directly. `--fast-only` disables escalation; `--deep` starts full P0-P6; `--audit` adds observability without changing solve rigor.

## Adaptive execution

- Always perform P0-Lite: authorization, artifact inventory, and separate target/build/runtime network classes.
- Skip generic P1 classification when the launcher already selected the category.
- Bound a Fast Probe to roughly 10 minutes, 8 major tool calls, 3 hypotheses, and 2 failed exploit trials.
- Treat launcher inactivity and wall-clock thresholds as status warnings only. They must never terminate Codex or challenge-solving subprocesses. A passed pwn primitive checkpoint must create and immediately advance the solver scaffold; checkpoint summaries preserve invariant, strategy, constraints, and next test.
- In Fast mode, keep state in the active session and create only the final solver and concise write-up. Do not continuously update notes, todo, command logs, or phase documents.
- Escalate without restarting when source is absent, the target is stripped/obfuscated, heap/race/probabilistic behavior appears, environment/protocol remains uncertain, local and official behavior differ, two exploit trials fail, or the fast budget expires.
- Reuse Fast results in Deep mode; never repeat completed discovery only to satisfy phase formatting.
- For pwn with a recorded official endpoint, run every newly local-successful solver version remotely at once to minimize local/remote drift. When exact local execution is unavailable, run the statically cross-checked first version and each materially corrected version. Do not impose a global attempt count or replay an unchanged solver automatically. A missing Dockerfile, cached image, or local flag must not block the first run. Run it before repeated controls, P5, or write-up, and print a remote flag and its measured acquisition time as soon as received.
- A retained exact image libc/loader pair may be used for one local-structure-only run before scarce remote attempts when a pwn chain is multi-stage, alignment-sensitive, or probabilistic. Keep image and supplied-libc calculations separate, instrument each remote stage, and never claim that this structural run validates remote offsets.
- Pwn solving must remain offline and independent: disable browser/web/search tools and never retrieve GitHub solutions, blogs, or challenge write-ups. Use only supplied artifacts, local tools, durable feedback, the controlled Docker build harness, and the exact recorded endpoint for bounded exploit execution.
- Absence of a Dockerfile is not a blocker or an escalation trigger by itself. If no matching cached image exists, declare `STATIC-ONLY`, continue with source/static analysis, avoid Docker retries or host execution, and request an exact runtime only when a decisive dynamic test is genuinely required.

## Shared execution environment

- Docker is available to every category agent and is the default boundary for untrusted executable content.
- GDB is available to every category agent when native-code debugging is relevant. Run or attach to challenge processes inside the Docker/sandbox boundary, not directly on the host.
- The local launcher may start Codex with `danger-full-access`; this does not authorize executing untrusted challenge content on the host. Keep such execution inside Docker.
- Do not calculate, require, or verify SHA-256 checksums during intake, analysis, execution, or reporting.

## Pipeline

| Phase | Owner | Required result |
|---|---|---|
| P0 Intake | root orchestrator | Authorization, scope, artifact inventory, network policy |
| P1 Triage | `.agents/triage-router.md` | Category, confidence, chosen specialist, plan |
| P2 Static map | specialist | Attack surface, hypotheses, cheapest tests |
| P3 Solve | specialist | Reproducible candidate solution and evidence |
| P4 Execute | `.agents/exploit-runner.md` | Sandboxed run log, constraints, repeatability |
| P5 Verify | `.agents/flag-verifier.md` | Independent flag validation; no guessing |
| P6 Write-up | `.agents/flag-verifier.md` | Sanitized solution notes and final state |

## Routing

- pwn -> `.agents/pwn-exploiter.md`, `pwn-agent/skills/SKILL.md`
- reverse engineering -> `.agents/rev-analyst.md`, `rev-agent/skills/SKILL.md`
- web -> `.agents/web-hacker.md`, `web-agent/skills/SKILL.md`
- crypto -> `.agents/crypto-breaker.md`, `references/categories/crypto.md`
- forensics, misc, OSINT, malware, AI/ML -> `.agents/forensics-analyst.md`

## Operating contract

- Keep raw inputs immutable and work on copies. Do not generate checksum records.
- Default to `work/solve.py` and a concise `work/writeup.md`. Create detailed notes, todo, command logs, and evidence packets only in Deep/Audit mode or when a long-running checkpoint is necessary.
- Separate observed facts, inferences, and hypotheses.
- Use the smallest test that can falsify a hypothesis.
- Do not scan unrelated hosts, pivot outside the challenge, contact real users, persist, or cause denial of service.
- Do not submit a flag or interact with a scoreboard unless the user explicitly asks.
- Stop and request direction if authorization, scope, destructive impact, or third-party boundaries are unclear.

## Completion gate

Declare solved only when the flag matches the recorded format and is reproduced from documented steps. Keep failed paths in session during Fast mode; persist them only after escalation, at a long-running checkpoint, or when they materially prevent repetition.
