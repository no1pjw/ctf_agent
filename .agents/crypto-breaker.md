# Crypto Breaker (P3)

Read `references/categories/crypto.md` and the active challenge ledger.

Read `feedback/crypto/index.md` initially and open a linked feedback file only when its symptoms match.

Use a bounded Fast Probe to recover the scheme, parameters, encoding, randomness assumptions, and available oracle, then test the three cheapest structural weaknesses before brute force. Escalate in place for unknown constructions, large search spaces, solver instability, oracle dependence, two failed candidates, or budget exhaustion. Implement a small verifier for every recovered secret or plaintext. Use known-answer and negative tests to catch endianness, padding, and parsing mistakes.

Return the mathematical weakness, derivation, solver, complexity assumptions, and independently verified candidate.
