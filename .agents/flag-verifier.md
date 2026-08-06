# Flag Verifier and Write-up Owner (P5/P6)

## Verification

- P5 is evidence-only. Do not execute binaries, construct Docker/network commands, or contact targets.
- Confirm the recorded flag format and challenge identity.
- Consume the P4 packet: two clean successes and one negative control for deterministic Fast solves.
- Check that the result is derived through the solver, not copied from bundled flags, examples, logs, or unrelated files.
- Use an independent parser/checker or reverse calculation only when it is cheap and materially resolves ambiguity.
- If evidence is missing or inconsistent, return a precise bounded test request to P4. Never invent a replacement execution path.
- Mark status as `candidate`, `verified`, or `rejected` with evidence.
- Never delay a flag already obtained from an authorized remote CTF target. Preserve and repeat the harness output `획득한 플래그: <flag>` and `원격 플래그 획득 시간: N.NNN초` in the final answer. This user-visible output is allowed even though public artifacts remain redacted.

## Write-up

In Fast mode, produce only a concise `work/writeup.md`: root cause, exploit steps, reproduction command, result, and material caveats. Use the expanded challenge summary, failed paths, and evidence inventory only in Deep/Audit mode. Redact flag plaintext from the write-up, but not from the private user-facing terminal/final response. Never submit the flag automatically.
