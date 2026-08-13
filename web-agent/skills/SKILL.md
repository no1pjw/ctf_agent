---
name: ctf-web
description: Solve explicitly authorized CTF web challenges from supplied source, isolated Docker services, or one exact remote HTTP(S) origin. Use for white-box and black-box web CTF tasks requiring bounded surface mapping, session and state analysis, request differentials, and the shortest reproducible flag path.
---

# CTF Web

1. Read `scope/web-scope.env` first. Use only the recorded loopback origin and exact remote origin; never follow a redirect to another origin.
2. If `input/` contains Compose or a Dockerfile, use `CTF_WEB_LOCAL_URL` first. If a local exploit returns a flag and `CTF_WEB_REMOTE_URL` exists, immediately replay the same minimal solver remotely. If source is absent, begin with one remote entry request using `CTF_WEB_PROBE` and build a small route/parameter/session map from observed responses and same-origin assets.
3. Select at most three cheap hypotheses from observed evidence. Test each with `baseline -> one mutation -> negative control when needed`; do not start with a generic vulnerability checklist.
4. Prioritize the shortest flag path: exposed route or asset, client-side trust, auth/state mismatch, IDOR, business invariant, parser confusion, then evidence-selected injection. Read `docs/blackbox.md` only for black-box tasks and `docs/vuln-map.md` only after the surface points to a class.
5. Keep requests bounded and sequential. Do not use broad scanners, recursive fuzzers, password brute force, DoS/races at scale, external callbacks, cloud metadata, adjacent hosts, or internet/write-up search.
6. Put the final reproducible request chain in `work/solve.py`. Run locally with `CTF_WEB_USE_LOCAL=1` and remotely without it. When a real remote flag—or a local flag for a local-only task—is returned, print `FLAG=<value>`, write `verified` to `work/.solved`, and stop immediately. Do not write a report before the flag.

If local runtime preparation fails but an exact authorized remote URL exists, continue black-box analysis against that URL. Missing source or Docker is not a blocker.
