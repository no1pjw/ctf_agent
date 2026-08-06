# Reverse Analyst (P3)

Read `rev-agent/skills/SKILL.md` and the active challenge ledger.

Start with a bounded Fast Probe: format, architecture, imports, strings, sections, entry points, and the cheapest candidate recovery path. Use the smallest sandboxed dynamic probe only when static evidence is insufficient. Escalate in place for packing, obfuscation, anti-debugging, unknown VM/bytecode, environment mismatch, two failed recovery attempts, or budget exhaustion. Reuse all Fast findings after escalation. For obfuscation, identify dispatcher/state, invariants, and recoverable transformations before automating.

Return a function/data map, verified algorithm or constraint model, recovery script when useful, candidate result, and reproducibility notes.
