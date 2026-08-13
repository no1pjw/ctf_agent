#!/usr/bin/env python3
import os
import re
from urllib.parse import urljoin, urlsplit

import requests


REMOTE_URL = os.environ.get("CTF_WEB_REMOTE_URL", "").strip()
REMOTE_ORIGIN = os.environ.get("CTF_WEB_REMOTE_ORIGIN", "").rstrip("/")
LOCAL_URL = os.environ.get("CTF_WEB_LOCAL_URL", "").strip()
LOCAL_ORIGIN = os.environ.get("CTF_WEB_LOCAL_ORIGIN", "").rstrip("/")
USE_LOCAL = os.environ.get("CTF_WEB_USE_LOCAL") == "1"


def origin(url):
    parsed = urlsplit(url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ValueError(f"invalid HTTP(S) URL: {url}")
    host = f"[{parsed.hostname}]" if ":" in parsed.hostname else parsed.hostname
    port = f":{parsed.port}" if parsed.port is not None else ""
    return f"{parsed.scheme.lower()}://{host.lower()}{port}"


if USE_LOCAL:
    ENTRY_URL, SCOPE_ORIGIN = LOCAL_URL, LOCAL_ORIGIN
else:
    ENTRY_URL = REMOTE_URL or LOCAL_URL
    SCOPE_ORIGIN = REMOTE_ORIGIN or LOCAL_ORIGIN
if not ENTRY_URL or not SCOPE_ORIGIN:
    raise SystemExit("no prepared Web CTF target is available")
if origin(ENTRY_URL) != SCOPE_ORIGIN:
    raise SystemExit("target URL does not match its recorded scope origin")

session = requests.Session()
session.trust_env = False
session.headers["User-Agent"] = "ctf-web-solver/1.0"
FLAG_RE = re.compile(r"[A-Za-z][A-Za-z0-9_]{0,31}\{[^\r\n{}]{1,512}\}")


def request(method, path_or_url="", **kwargs):
    url = urljoin(ENTRY_URL, path_or_url) if path_or_url else ENTRY_URL
    if origin(url) != SCOPE_ORIGIN:
        raise ValueError(f"out-of-scope request blocked: {url}")
    kwargs.setdefault("timeout", 8)
    kwargs.setdefault("allow_redirects", False)
    return session.request(method, url, **kwargs)


def find_flag(value):
    if isinstance(value, bytes):
        value = value.decode(errors="replace")
    match = FLAG_RE.search(value or "")
    return match.group(0) if match else None


def solve():
    """Implement the shortest evidence-derived request chain and return the flag."""
    raise NotImplementedError


if __name__ == "__main__":
    flag = solve()
    if isinstance(flag, bytes):
        flag = flag.decode(errors="strict")
    if not isinstance(flag, str) or not FLAG_RE.fullmatch(flag):
        raise SystemExit("solve() did not return a validated flag")
    print(f"FLAG={flag}", flush=True)
