# Playbook

1. Read `work/web-runtime.env`, `scope/web-scope.env`, the supplied Compose/Dockerfile, and service logs. Record the loopback origin, reset method, accounts, source revision, and runtime.
2. Map endpoints, methods, roles, state transitions, and trust boundaries from source before sending requests.
3. Trace attacker-controlled data through validation, storage, and sinks.
4. Rank hypotheses by likelihood, impact, and test cost.
5. Send a baseline, one controlled mutation, and a negative control only to `CTF_WEB_BASE_URL`.
6. Explain the violated security invariant and derive the flag path.
7. Put the minimal reproduction in `work/solve.py`, reproduce from clean state, and stop as soon as the flag is verified. Keep only the final exploit and concise write-up unless audit mode is requested.
