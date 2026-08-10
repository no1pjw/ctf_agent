# Ruleset

## R-1 Authorization and scope

Work only on official CTF infrastructure, challenge artifacts supplied by the user, or user-owned local labs. Record the authorization basis and exact allowed hosts before any network request. Discovery outside the declared host, port, and protocol is forbidden.

## R-2 Safe execution

Treat binaries, documents, packet captures, scripts, containers, and models as untrusted. Inspect statically first. Docker is available to every category and is the default execution boundary. Run only in the `sandbox/` boundary with resource limits, no secrets, a disposable working copy, and networking disabled unless the challenge explicitly requires it. Use GDB when relevant, but debug challenge processes inside that boundary rather than directly on the host.

## R-3 Network policy

Classify networking before use:

- Target network: deny by default; allow only the exact recorded official challenge endpoint.
- Build network: allow only through the deterministic build harness for a supplied Dockerfile. Reuse an existing image unless `--rebuild` is requested. Do not add checksum or digest-verification gates.
- Runtime network: use `--network none` by default. Keep local service/client interaction inside the isolated container when practical.

Never treat build dependency access as authorization for target traffic. Stop on unexpected redirects, third parties, or runtime egress.

For pwn challenges, a host and port explicitly supplied to `ctf-pwn` or `ctf-bench` records one official TCP endpoint. For `ctf-pwn`, every newly local-successful solver version triggers an immediate remote harness run so local/remote drift is discovered early. If exact local execution is unavailable, a statically cross-checked and syntax-valid first version and each materially corrected version may run remotely without a Dockerfile, cached image, or local flag. Do not impose a global count, delay for repeat controls, or replay an unchanged solver automatically. This authorization does not include port scanning, neighboring hosts, scoreboard access, brute force, flooding, persistence, or lateral movement. Benchmark-specific attempt policy remains isolated to `ctf-bench`.

When an incompatible pwn manifest retains an exact image libc/loader pair, one sandboxed local-structure-only run is permitted before a scarce remote attempt for a multi-stage, alignment-sensitive, or probabilistic chain. It may validate framing, pivot, alignment, and stage order, but not supplied-libc remote offsets. Keep both profiles explicit and require secret-free stage diagnostics before spending the remote attempt.

Pwn solving is offline-first and solution lookup is prohibited. Do not browse the web, use search engines or GitHub search, retrieve blogs/write-ups, or use shell/MCP/browser/computer tools to obtain challenge solutions. The only target-network exception is the exact recorded endpoint through the bounded exploit client. Controlled dependency access by the supplied Docker build harness is a separate build-network class and does not authorize research browsing.

For local Web challenges, `ctf-web` records one loopback origin after starting a sanitized supplied Compose project or Dockerfile image. Compose has priority. Published ports must bind to loopback, runtime networks must be internal, and privileged mode, host namespaces, devices, external networks, and bind mounts outside the disposable service copy are forbidden. HTTP clients may contact only the recorded origin; redirects never broaden scope. Build dependency traffic remains separate from runtime traffic.

## R-4 Evidence

In default Fast mode, retain the final solver, decisive output, environment assumptions, and verification controls. Before a validated flag is printed, do not create, update, or read a write-up; documentation cannot delay a ready exploit attempt. A concise write-up may be produced only after that gate and is skipped for benchmark flag-short-circuit runs. Detailed command logs, timestamps, phase notes, and raw evidence packets are required only in Deep/Audit mode or for a long-running checkpoint. Never generate or check SHA-256 records; redact tokens, personal data, and flags from public write-ups when required.

Storage compaction must never delete category feedback, `work/solve.py`, `work/writeup.md`, `scope`, or `evidence/private`. Duplicate challenge inputs may be removed only after completion and only when a readable external source copy is recorded or discoverable. Incomplete challenges and unknown files are preserved. Rebuildable language caches and core dumps are not learning records.

Bound operational memory: `work/state.json` retains at most 20 compact stage transitions, remote transcripts default to 1 MiB, and full dumps belong only in a disposable sandbox. Existing category feedback is durable knowledge and is never pruned by workspace or cache cleanup.

Launchers do not terminate active solves or emit file-inactivity/time heartbeat warnings. Cleanup may target only Docker resources for the named challenge and processes that inherited the current run ID; never kill unrelated or pre-existing processes.

## R-5 Reproducibility

For deterministic Fast solves without a remote endpoint, require two clean P4 successes and one negative control. When an official pwn endpoint is recorded, each new local success triggers an immediate remote run before those controls; without an exact local runtime, use an independent static cross-check for the first and each materially corrected solver. A format-valid flag derived by that remote exploit is the contest completion signal. On remote failure, compare the exact runtime profile and failed stage before the next corrected local/remote cycle. A crash, anomaly, or plausible plaintext is not by itself a verified result.

## R-6 Exploit limits

Minimize payloads and side effects. No persistence, lateral movement, credential reuse, real-user access, destructive writes, resource exhaustion, or activity after obtaining the minimum proof needed for the challenge.

## R-7 Flag handling

Validate against the recorded flag format and derivation path. Never brute-force a scoreboard or automatically submit. Store candidate flags only in the challenge's private evidence area.

## R-8 Handoffs

Every handoff states: inputs, observed facts, hypotheses, commands already tried, artifacts produced, blockers, and next cheapest test.

## R-9 Stop conditions

Stop on uncertain authorization, scope drift, unexpected external systems, destructive behavior, secrets unrelated to the challenge, possible real-person data, or inability to contain an artifact safely.
