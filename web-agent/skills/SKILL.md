---
name: ctf-web
description: Analyze and solve explicitly authorized CTF web challenges from supplied source, local containers, or exact official challenge origins. Use for route and trust-boundary mapping, authentication and authorization logic, parser behavior, injection, request smuggling simulations, browser-side flaws, and reproducible flag derivation.
---

# CTF Web

Read `../docs/HARD_RULES.md`, then `../docs/role.md` and `../docs/playbook.md`. Read the active challenge ledger and `../../rules/ruleset.md`.

1. Read `work/web-runtime.env` first. The launcher starts a supplied Compose file before a standalone Dockerfile and records the only allowed loopback origin. If neither exists, remain STATIC-ONLY until a minimal work-only container is justified.
2. Record the exact allowed origin, accounts, methods, and rate constraints before remote traffic.
3. In a bounded Fast Probe, read only `../feedback/index.md` initially and open a linked feedback file only when its symptoms match. Map only the routes, state, roles, parsers, and trust boundary needed for the top three cheap hypotheses; escalate in place for complex state, remote-only behavior, repeated failure, or budget exhaustion.
4. Review source routes and trust boundaries before traffic. Test a single hypothesis against `CTF_WEB_BASE_URL` with baseline, changed condition, and negative control.
5. Keep only decisive requests and responses in Fast mode; redact credentials. Create detailed traces only in Deep/Audit mode.
6. Avoid broad scanners, unrelated origins, third-party callbacks, and disruptive payloads.
7. Modify the prepared `work/solve.py` into the shortest reproducible solver. Reproduce the flag path from a clean container state, explain the violated invariant, print the verified flag immediately, and stop.

Return the invariant, minimal reproduction, evidence, source path when known, candidate flag derivation, and limits.
