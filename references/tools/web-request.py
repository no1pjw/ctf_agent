#!/usr/bin/env python3
"""Send one exact-origin Web CTF request and save bounded private evidence."""

import argparse
import json
import os
from pathlib import Path
from urllib.parse import urljoin, urlsplit

import requests


def origin(url):
    parsed = urlsplit(url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ValueError("URL must be absolute HTTP(S)")
    host = f"[{parsed.hostname}]" if ":" in parsed.hostname else parsed.hostname
    port = f":{parsed.port}" if parsed.port is not None else ""
    return f"{parsed.scheme.lower()}://{host.lower()}{port}"


def target(kind):
    if kind == "local":
        return os.environ.get("CTF_WEB_LOCAL_URL", ""), os.environ.get("CTF_WEB_LOCAL_ORIGIN", "")
    if kind == "remote":
        return os.environ.get("CTF_WEB_REMOTE_URL", ""), os.environ.get("CTF_WEB_REMOTE_ORIGIN", "")
    remote = os.environ.get("CTF_WEB_REMOTE_URL", "")
    if remote:
        return remote, os.environ.get("CTF_WEB_REMOTE_ORIGIN", "")
    return os.environ.get("CTF_WEB_LOCAL_URL", ""), os.environ.get("CTF_WEB_LOCAL_ORIGIN", "")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("path", nargs="?", default="")
    parser.add_argument("--target", choices=("auto", "local", "remote"), default="auto")
    parser.add_argument("--method", default="GET")
    parser.add_argument("--header", action="append", default=[])
    parser.add_argument("--data")
    parser.add_argument("--json")
    parser.add_argument("--cookies")
    parser.add_argument("--output", required=True)
    parser.add_argument("--meta", required=True)
    parser.add_argument("--timeout", type=float, default=8.0)
    parser.add_argument("--max-bytes", type=int, default=2_000_000)
    args = parser.parse_args()

    base, scope = target(args.target)
    scope = scope.rstrip("/")
    if not base or not scope or origin(base) != scope:
        raise SystemExit(f"prepared {args.target} target is unavailable")
    url = urljoin(base, args.path) if args.path else base
    if origin(url) != scope:
        raise SystemExit(f"out-of-scope request blocked: {url}")

    headers = {}
    for raw in args.header:
        if ":" not in raw:
            raise SystemExit(f"invalid header: {raw}")
        name, value = raw.split(":", 1)
        if name.strip().lower() in {"host", "forwarded", "x-forwarded-host"}:
            raise SystemExit(f"scope-sensitive header is blocked: {name.strip()}")
        headers[name.strip()] = value.lstrip()
    cookies_path = Path(args.cookies) if args.cookies else None
    cookies = {}
    if cookies_path and cookies_path.exists():
        cookies = json.loads(cookies_path.read_text(encoding="utf-8"))

    kwargs = {"data": args.data} if args.data is not None else {}
    if args.json is not None:
        kwargs = {"json": json.loads(args.json)}
    session = requests.Session()
    session.trust_env = False
    response = session.request(
        args.method.upper(), url, headers=headers, cookies=cookies,
        timeout=args.timeout, allow_redirects=False, stream=True, **kwargs,
    )
    body = bytearray()
    for chunk in response.iter_content(65536):
        body.extend(chunk)
        if len(body) > args.max_bytes:
            raise SystemExit(f"response exceeded {args.max_bytes} bytes")

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(body)
    metadata = {
        "url": url,
        "method": args.method.upper(),
        "status": response.status_code,
        "content_type": response.headers.get("Content-Type"),
        "content_length": len(body),
        "location": response.headers.get("Location"),
        "set_cookie_names": sorted(response.cookies.keys()),
    }
    meta = Path(args.meta)
    meta.parent.mkdir(parents=True, exist_ok=True)
    meta.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if cookies_path:
        merged = dict(cookies)
        merged.update(response.cookies.get_dict())
        cookies_path.parent.mkdir(parents=True, exist_ok=True)
        cookies_path.write_text(json.dumps(merged, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(metadata, ensure_ascii=False))


if __name__ == "__main__":
    main()
