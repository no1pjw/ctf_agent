# CTF Agent Orchestrator

## User-facing language

Write every user-visible progress update, decision, error explanation, question, and final answer in Korean by default. Preserve commands, code, paths, symbols, flags, protocol tokens, and verbatim diagnostic text in their original form when translation could reduce accuracy.

## Learning mode

When `$ctf-learn` is invoked, do not enter the P0-P6 solve pipeline. Read `learn-agent/skills/ctf-learn/SKILL.md`, review only the completed challenge artifacts needed to extract lessons, and modify only the feedback directory named in the prompt. Do not execute challenge artifacts, contact a target, change core skills/policies/tools, or store challenge-specific answers.

Operate only on CTF challenges, local labs, and systems for which the user has explicit authorization. Treat every supplied host as out of scope until its CTF context and allowed target are recorded in the challenge ledger.

## Startup

When a launcher already selected a category, its specialist skill is the single execution contract: do not preload `ruleset.md`, role/playbook documents, global notes, or unrelated feedback. Read a longer reference only after a concrete blocker identifies it.

1. For an unclassified manual session, read `rules/ruleset.md`, `state/notes.md`, and `state/todo.md`.
2. Create or select `challenges/<challenge-id>/` and record source, category, scope, flag format, artifacts, and network allowance.
3. Never execute an untrusted artifact outside `sandbox/`. Prefer offline inspection first.
4. Route work through the phase owners below. A phase may be repeated when evidence changes.

Adaptive mode is the default for every category: P0-Lite, fixed routing when the launcher already knows the category, a bounded specialist Fast Probe, P5-Lite, and automatic in-place escalation to the full P0-P6 workflow only when a defined trigger fires. `ctf-pwn <challenge-name>`, `ctf-rev <challenge-name>`, and `ctf-web <challenge-name>` implement this for local pwn, reversing, and Web intake. `--fast-only` disables escalation; `--deep` starts full P0-P6; `--audit` adds observability without changing solve rigor.

## Adaptive execution

- Always perform P0-Lite: authorization, artifact inventory, and separate target/build/runtime network classes.
- Skip generic P1 classification when the launcher already selected the category.
- Bound a Fast Probe to roughly 10 minutes, 8 major tool calls, 3 hypotheses, and 2 failed exploit trials.
- Launchers do not emit inactivity/wall-clock warnings and must never terminate an active solve. A passed pwn primitive checkpoint must create and immediately advance the solver scaffold; checkpoint summaries preserve invariant, strategy, constraints, and next test.
- In Fast mode, keep state in the active session and create the solver first. Before a validated flag is printed, do not create, update, or read a write-up; retain only the smallest required checkpoint or private transcript. A concise write-up is post-flag work and is skipped when success short-circuits the session.
- Escalate without restarting when source is absent, the target is stripped/obfuscated, race/probabilistic behavior appears, environment/protocol remains uncertain, local and official behavior differs, two evidence-bearing exploit trials fail, or the fast budget expires. Heap usage alone is not an escalation trigger when a direct primitive and short flag path are already concrete.
- Reuse Fast results in Deep mode; never repeat completed discovery only to satisfy phase formatting.
- For pwn, route all runtime, offline solving, fast-to-remote, and completion details to `pwn-agent/skills/SKILL.md`; do not restate or expand them during startup.
- For reversing, route static mapping, sandboxed execution, recovery, verification, and completion details to `rev-agent/skills/SKILL.md`. Do not preload its longer docs or feedback index.
- For Web challenges, inspect and start a supplied Compose file before a standalone Dockerfile. Run a disposable source copy, rebind published ports to loopback, make runtime networks internal, reject unsafe host/device/privileged access, and record the origin in `work/web-runtime.env` before HTTP traffic.

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
- Default to `work/solve.py` during solving. Create `work/writeup.md` only after the validated flag has already been printed to the user. Create detailed notes, todo, command logs, and evidence packets only in Deep/Audit mode or when a long-running checkpoint is necessary.
- Separate observed facts, inferences, and hypotheses.
- Use the smallest test that can falsify a hypothesis.
- Do not scan unrelated hosts, pivot outside the challenge, contact real users, persist, or cause denial of service.
- Do not submit a flag or interact with a scoreboard unless the user explicitly asks.
- Stop and request direction if authorization, scope, destructive impact, or third-party boundaries are unclear.

## Completion gate

Declare solved only when the flag matches the recorded format and is reproduced from documented steps. Keep failed paths in session during Fast mode; persist them only after escalation, at a long-running checkpoint, or when they materially prevent repetition.
