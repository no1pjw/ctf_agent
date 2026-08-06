# Hard rules

- Only attack the recorded challenge binary or official endpoint.
- Do not brute-force shared infrastructure or exhaust resources.
- Do not execute shell payloads on the host.
- Do not hide probabilistic exploit behavior or environment coupling.
- Stop after the minimum challenge proof; never pivot.
- Treat a CLI-supplied endpoint as authorization for that exact TCP host and port only. Allow at most two bounded exploit attempts after local validation; never scan or automatically submit the resulting flag.
