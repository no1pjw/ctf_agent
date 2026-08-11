# Failure ledger

Record failed primitive or exploit path, debugger evidence, environment, and the next discriminating test.

- Docker stdin-driven challenges require `--interactive`; use `pwn-run.sh` to prevent silent EOF mistakes.
- `pwn-run.sh IMAGE` is not a harmless probe: an image CMD may be a permanent service. Use an explicit terminating command, or `--service` only inside the solver. If a timed service does not exit on TERM, the harness must KILL the Docker client after a short grace and remove only the recorded container CID.
- For unmatched trailing scanf conversions, test EOF/half-close in the supplied libc before broad environment analysis.
- Do not let P5 invent execution or network commands; return missing-evidence requests to P4.
- A missing Dockerfile is not a reason to loop on environment setup. Use `STATIC-ONLY`; never create or pull a guessed runtime unless the user later supplies or authorizes an exact environment.
- Compare Docker `COPY` destinations with the executable referenced by the service wrapper before trusting local equivalence. A renamed or missing entrypoint can make a correct primitive look environment-dependent; `pwn-intake-check.sh` is the cheapest discriminator.
- When official attempts are scarce, add stage and bounded raw-length diagnostics before the first attempt. A blank EOF without the last passed stage wastes the attempt and cannot distinguish framing, pivot, leak, or alignment failure.
