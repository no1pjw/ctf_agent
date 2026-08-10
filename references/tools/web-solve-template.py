#!/usr/bin/env python3
import os
import re
from urllib.parse import urljoin, urlparse

import requests


BASE_URL = os.environ.get("CTF_WEB_BASE_URL", "").rstrip("/")
parsed = urlparse(BASE_URL)
if parsed.scheme not in {"http", "https"} or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}:
    raise SystemExit("CTF_WEB_BASE_URL must be the prepared loopback challenge origin")

session = requests.Session()
session.headers["User-Agent"] = "ctf-web-local-solver/1.0"
FLAG_RE = re.compile(r"(?:DH|FLAG|CTF)\{[^\r\n{}]{1,512}\}")


def request(method, path, **kwargs):
    url = urljoin(BASE_URL + "/", path.lstrip("/"))
    response = session.request(method, url, timeout=5, allow_redirects=False, **kwargs)
    return response


def solve():
    """Implement the shortest source-derived local exploit and return the flag."""
    raise NotImplementedError


if __name__ == "__main__":
    flag = solve()
    if isinstance(flag, bytes):
        flag = flag.decode(errors="strict")
    if not isinstance(flag, str) or not FLAG_RE.fullmatch(flag):
        raise SystemExit("solve() did not return a validated flag")
    print(f"FLAG={flag}", flush=True)
