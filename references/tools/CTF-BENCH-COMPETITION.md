# CTF benchmark competition mode

`ctf-bench-*` runs `gpt-5.6-luna`, `gpt-5.6-terra`, and `gpt-5.6-sol` in parallel with `max` reasoning and the fast service tier.

Each participant receives the same category Agent context:

- pwn: `ctf-pwn` skill, intake, checkpoint, supplied/image libc+ld runtime, and the shared Docker image;
- rev: `ctf-rev` skill, intake, `recover.py`, FAST probe, flag-success helper, and the shared Docker image;
- web: `ctf-web` skill, probe/request tools, solver template, and the prepared Compose/Dockerfile loopback runtime when available.

Candidates are exchanged only inside the current run:

```sh
"$CTF_BENCH_COLLAB_TOOL" publish "pivot candidate" "offset=72; validate with one bounded replay"
"$CTF_BENCH_COLLAB_TOOL" list
"$CTF_BENCH_COLLAB_TOOL" read <candidate-file>
```

The shared directory is `benchmarks/runs/<category>/<run-id>/collab/candidates/`. Candidate notes are advisory; each model must validate them. A verified flag is never accepted from a candidate file. It must arrive through the `FLAG=` output contract (or the bounded remote harness marker), which atomically declares the winner and terminates the other model process groups.

Internal Codex subagents are enabled. Each model may delegate static analysis, validation, or solver construction in parallel; the three top-level models still share the same category pipeline and candidate channel.
