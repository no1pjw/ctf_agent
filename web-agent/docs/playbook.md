# Playbook

## Fast path

1. Read `scope/web-scope.env`, then `work/web-runtime.env` when present. If both local and remote origins exist, validate locally and replay remotely without redesigning the exploit.
2. Inspect supplied source and static assets before traffic. For black-box input, make one entry request and inventory observed methods, parameters, forms, scripts, cookies, redirects, and error shapes.
3. Describe the smallest state model: anonymous/authenticated role, owned object, current workflow state, and server-side invariant.
4. Rank no more than three hypotheses by flag likelihood and request cost.
5. Test one baseline and one changed dimension. Add a negative control only when status/body differences are ambiguous.
6. As soon as a primitive works, turn it into the shortest end-to-end `work/solve.py`. Run `CTF_WEB_USE_LOCAL=1 python3 work/solve.py` once when local runtime exists, then immediately run `python3 work/solve.py` against the exact remote target.

## Evidence-directed expansion

- Object identifiers or owner fields: compare self, one controlled alternate object, and missing auth.
- Hidden/disabled UI action: call the observed same-origin route directly and compare server authorization.
- Multi-step workflow: replay, skip, reorder, or duplicate one step while tracking the expected state invariant.
- JSON/API: vary one field, method, content type, version, or auth state at a time.
- Template/query/path/upload sink: use one harmless syntax canary before constructing a flag-bearing payload.
- JavaScript application: extract same-origin endpoints, source maps, feature flags, client-side role checks, and embedded challenge data before guessing paths.

After two evidence-backed failures, rotate to the fallback hypothesis. Enter Deep only for protocol ambiguity, multi-role/state chains, a strong blind oracle, or environment mismatch. Never broaden the host or search the public web.
