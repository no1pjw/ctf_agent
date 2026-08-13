# Evidence-to-test map

Load only the row supported by the current surface.

| Evidence | First low-cost test | Invariant |
|---|---|---|
| Object ID, filename, UUID, owner field | Change one controlled identifier or remove auth | Only the authorized owner can read or mutate it |
| Hidden/admin UI action | Replay the observed endpoint as the current role | Server authorization cannot depend on the client UI |
| Multi-step/coupon/redeem/claim flow | Skip, reorder, or replay one transition | State advances once and only from a valid predecessor |
| JSON update/create | Add one server-managed field | Clients cannot assign role, owner, balance, or approval state |
| URL/path/file parameter | Harmless same-origin canary or normalized traversal | The server cannot cross the intended resource boundary |
| Template-like rendering | One arithmetic canary such as `{{7*7}}` | User input is data, not template code |
| Query/filter/search | Quote/type/error differential, then a control | User input cannot change query structure |
| Upload/filename/content type | Benign extension/MIME mismatch | Validation and storage agree on file identity |
| GraphQL/schema response | Introspection if exposed, then one owned object | Resolver authorization applies per object and mutation |
| Redirect/next/callback | Same-origin alternate path only | Navigation remains within the intended origin and flow |
| JWT/session cookie | Remove or alter one non-destructive claim/token property | Server validates integrity, audience, expiry, and role |
| JavaScript route/feature flag | Direct same-origin request | Client code cannot be the security boundary |

Do not automatically escalate to SQLi, SSRF, XSS, or file execution merely because a parameter name resembles a sink. Require a response differential or source evidence first.
