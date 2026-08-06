---
name: ctf-web
description: Analyze and solve explicitly authorized CTF web challenges from supplied source, local containers, or exact official challenge origins. Use for route and trust-boundary mapping, authentication and authorization logic, parser behavior, injection, request smuggling simulations, browser-side flaws, and reproducible flag derivation.
---

# CTF Web

Read `../docs/HARD_RULES.md`, then `../docs/role.md` and `../docs/playbook.md`. Read the active challenge ledger and `../../rules/ruleset.md`.

1. Prefer source review and local deployment.
2. Record the exact allowed origin, accounts, methods, and rate constraints before remote traffic.
3. In a bounded Fast Probe, read only `../feedback/index.md` initially and open a linked feedback file only when its symptoms match. Map only the routes, state, roles, parsers, and trust boundary needed for the top three cheap hypotheses; escalate in place for complex state, remote-only behavior, repeated failure, or budget exhaustion.
4. Test a single hypothesis with baseline, changed condition, and negative control.
5. Keep only decisive requests and responses in Fast mode; redact credentials. Create detailed traces only in Deep/Audit mode.
6. Avoid broad scanners, unrelated origins, third-party callbacks, and disruptive payloads.
7. Reproduce the flag path from a clean state and explain the violated invariant. Write only the final solver/reproduction and concise write-up by default.

Return the invariant, minimal reproduction, evidence, source path when known, candidate flag derivation, and limits.
