# Hard rules

- Only attack the recorded challenge binary or official endpoint.
- Do not brute-force shared infrastructure or exhaust resources.
- Do not execute shell payloads on the host.
- Do not hide probabilistic exploit behavior or environment coupling.
- Stop after the minimum challenge proof; never pivot.
- Treat a CLI-supplied endpoint as authorization for that exact TCP host and port only. Use local validation when an exact runtime exists; otherwise a statically cross-checked, syntax-valid remote client may make the first bounded attempt without running the target binary on the host. Allow at most two bounded attempts and never scan or automatically submit the resulting flag.
