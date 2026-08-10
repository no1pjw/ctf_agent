# Hard rules

- Do not broaden scope through redirects, DNS, links, callbacks, or shared infrastructure.
- Do not use broad automated scans against remote challenges.
- Do not access real-user data, reuse credentials, or contact third parties.
- Do not perform denial of service or irreversible state changes.
- Do not send remote requests until the exact authorized origin is recorded.
- For local challenges, send HTTP only to the loopback origin in `work/web-runtime.env`; never follow a redirect to another origin.
- Never start a supplied Web service directly on the host. Use the sanitized Compose project first, otherwise the supplied Dockerfile image.
- Reject privileged containers, host namespaces, devices, external Docker networks, and bind mounts outside the disposable service copy.
