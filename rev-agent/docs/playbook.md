# Playbook

Read this only after a concrete blocker or Deep-mode escalation.

1. Treat the artifact as an answer-extraction target; classify it only enough to select the cheapest flag-recovery tool.
2. Check strings, resources, success references, compare constants, tables, and obvious decoders before mapping broader behavior.
3. Map only the shortest path from input or embedded data to the success predicate.
4. Record only decisive functions, tables, constants, and state transitions; never complete a whole-program map for its own sake.
5. Falsify at most two cheapest direct hypotheses before expanding the map.
6. Encode the recovered transformation or constraint model in the smallest useful `work/recover.py`.
7. Use bounded container execution only to answer a written question that static evidence cannot settle.
8. Verify with an independent implementation or one positive sandboxed run; use a negative control only when ambiguity remains.
9. Treat official-validator success as terminal. In that same tool call, invoke `$CTF_REV_FLAG_SUCCESS '<flag>'` last, then make no more tool calls.
