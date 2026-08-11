# QEMU session and transport lifecycle

Use this when a pwn target is wrapped by QEMU, a serial console, or a containerized service and the exploit appears correct but sessions terminate, collide, or exhaust resources.

## Symptoms

- A first connection reaches the guest but later connections fail before the exploit stage.
- The runner enables a fixed debugger or monitor port and parallel sessions report an address collision.
- Large encoded uploads are truncated even though the local payload is valid.
- Containers use `--rm` but remain alive, or new processes fail with resource-exhaustion errors.
- A remote harness starts the solver, but the solver executes its local branch.

## Durable response

1. Inspect the runner once for fixed `-s`, `-gdb`, monitor, serial, and forwarded-port settings. Treat a fixed-port collision as a session-lifecycle failure; do not spend exploit attempts changing the payload.
   Never start the image's default CMD as a standalone probe. Use an explicit terminating inspection command, or launch it with `pwn-run.sh --service` from the solver that will consume and close the session.
2. Serialize sessions that share a fixed internal port, or give benchmark variants isolated instances. Do not assume two clients can safely share one QEMU service.
3. Validate the solver/harness contract before official traffic. The remote switch and supplied host/port must select the remote branch, and stage diagnostics must distinguish transport, upload, trigger, and flag-read failures.
4. For serial uploads, compress and encode once, send bounded chunks, and wait for the guest prompt after every chunk. After one truncation, switch framing instead of retrying the same large write.
5. `--rm` removes a container only after its main process exits. Never leave a post-result `pause()` loop. On local success or failure, terminate the guest through its supported monitor escape or poweroff path; on remote success, close only the client socket.
6. Audit and remove only challenge-owned containers after each local probe. If process creation starts failing, stop launching probes and clean owned resources before continuing.
7. A local service timeout is a failed dynamic probe, not the end of the solve. Require TERM followed by a short KILL grace for the Docker client and CID-scoped container removal, then continue from static evidence or the exact endpoint.

## Cheapest checks

- Read the runner and compose files; do not start another instance merely to discover fixed ports.
- Confirm the solver's selected mode and endpoint without connecting.
- Record bounded stage names and byte counts rather than full serial logs.
- Check challenge labels and live container count before another local run.

## Limits

- Never kill unrelated host or user processes to recover resources.
- A remote service may preserve a prior QEMU instance after the socket closes; reconnecting repeatedly can make the environment worse.
- Keep service lifecycle failures separate from exploit-logic failures in notes and feedback.

This feedback contains no challenge-specific addresses, flags, payloads, or endpoint data.
