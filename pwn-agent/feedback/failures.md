# Failure ledger

Record failed primitive or exploit path, debugger evidence, environment, and the next discriminating test.

- Docker stdin-driven challenges require `--interactive`; use `pwn-run.sh` to prevent silent EOF mistakes.
- For unmatched trailing scanf conversions, test EOF/half-close in the supplied libc before broad environment analysis.
- Do not let P5 invent execution or network commands; return missing-evidence requests to P4.
- A missing Dockerfile is not a reason to loop on environment setup. Use `STATIC-ONLY`; never create or pull a guessed runtime unless the user later supplies or authorizes an exact environment.
- Compare Docker `COPY` destinations with the executable referenced by the service wrapper before trusting local equivalence. A renamed or missing entrypoint can make a correct primitive look environment-dependent; `pwn-intake-check.sh` is the cheapest discriminator.
- When official attempts are scarce, add stage and bounded raw-length diagnostics before the first attempt. A blank EOF without the last passed stage wastes the attempt and cannot distinguish framing, pivot, leak, or alignment failure.
