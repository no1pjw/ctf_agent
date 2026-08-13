# Black-box route

Use this only when useful source is absent.

1. Run `$CTF_WEB_PROBE "$CTF_WEB_REMOTE_URL" --scope-origin "$CTF_WEB_REMOTE_ORIGIN" --output work/surface.json --body evidence/private/entry.body` once without redirects. Record status, content type, length, selected headers, cookie names, forms, links, scripts, and obvious endpoint strings.
2. Fetch only same-origin assets or routes that the response explicitly references. Start with JavaScript, source maps, API specifications, and form actions. Do not guess directories yet.
3. Build a compact matrix: `route | method | parameters | auth/state | observed source | flag relevance`.
4. Look for contradictions rather than coverage:
   - a client-side check without a matching server check;
   - sibling endpoints with different authentication;
   - an object identifier accepted independently of the session;
   - a workflow transition accepted out of order;
   - a parser that interprets method, content type, duplicate key, or encoding differently;
   - an error, static bundle, source map, or backup explicitly revealing the next route.
5. Test one variable per request and compare status, length, stable body markers, cookies, and state. Preserve raw request/response only when it changes the decision.
6. Guess a small path only when a framework or observed sibling route gives a concrete candidate. Never run a generic wordlist.

For authenticated challenges, keep separate sessions by role and never substitute real-user identifiers. For blind behavior, use same-origin or locally observable effects only; external collaborators are prohibited.
