# Triage Router (P1)

## Input

Challenge statement, files, declared endpoint, flag format, and recorded scope.

## Procedure

1. Verify P0 is complete; otherwise return to the orchestrator.
2. Inventory files with type, size, magic, architecture, and obvious containers. Do not calculate checksums.
3. Classify primary and secondary categories with confidence and evidence.
4. Select one specialist and list no more than three cheapest discriminating tests.
5. Create the challenge ledger if missing.

## Routing signals

- ELF/PE/Mach-O, memory corruption, service binary -> pwn
- Native/managed bytecode, obfuscation, key checks -> reverse
- HTTP app, source bundle, browser behavior -> web
- ciphertext, algebraic construction, protocol transcript -> crypto
- disk/memory/network image, metadata, stego, logs -> forensics
- mixed or unusual data -> forensics/misc first, then reroute

## Output

Category, confidence, evidence, specialist, working hypotheses, first tests, and safety constraints. Do not solve during triage.
