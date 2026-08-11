# Hard rules

- Only attack the recorded challenge binary or official endpoint.
- Do not brute-force shared infrastructure or exhaust resources.
- Do not execute shell payloads on the host.
- Never use a bare `pwn-run.sh IMAGE` call as a health check or background probe. Supply a terminating command, or use explicit `--service` only from a solver that owns the service I/O and shutdown. A harness timeout may force-remove only its own container; it must not terminate the Codex solve.
- Do not hide probabilistic exploit behavior or environment coupling.
- Stop after the minimum challenge proof; never pivot.
- Solve from the supplied artifacts and durable local `ctf-learn` feedback. Never browse the web, query a search engine, search GitHub, fetch blogs, or retrieve public/private challenge write-ups. Do not use `curl`, `wget`, package APIs, MCP apps, browser/computer tools, or shell networking to obtain solution material. The exact recorded official endpoint remains allowed only for the bounded exploit client, and controlled Docker build networking remains limited to the supplied build harness.
- Treat a CLI-supplied endpoint as authorization for that exact TCP host and port only. Use local validation when an exact runtime exists; otherwise a statically cross-checked, syntax-valid remote client may run without executing the target binary on the host. Do not impose a global attempt count: immediately test each newly local-successful solver remotely, and test each materially corrected solver when local execution is unavailable. Never replay an unchanged exploit automatically, brute-force, flood, scan, or automatically submit the resulting flag.
- Do not create, update, or read `work/writeup.md` before a validated flag is printed. A ready exploit attempt always precedes documentation; write-up work is post-flag only and is skipped entirely when a benchmark short-circuits on success.
