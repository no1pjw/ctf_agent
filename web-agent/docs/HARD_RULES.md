# Hard rules

- Treat only the user-supplied CTF artifact, launcher-created loopback origin, and exact recorded remote HTTP(S) origin as authorized.
- Resolve and send every request through one recorded origin. Disable redirects and reject any different scheme, host, or port. Never copy a remote redirect into the local scope or vice versa.
- Never enumerate subdomains, scan ports or adjacent hosts, contact third parties, use external callbacks, or search for write-ups.
- Never use credential stuffing, account lockout tests, destructive state changes, bulk extraction, resource exhaustion, or high-concurrency races.
- Use only challenge-created identities and data. Stop at the first flag or minimum proof needed to reach it.
- Start supplied services only through the sanitized Compose/Docker runtime. Never run an untrusted server directly on the host.
- Keep cookies, tokens, raw responses, and flags under `evidence/private` or `work`; do not copy secrets into feedback.
- A local runtime failure does not prohibit the exact authorized remote challenge URL, but it never authorizes any other network destination.
