#!/usr/bin/env python3
"""Make one bounded exact-origin request and extract a compact Web CTF surface map."""

import argparse
import json
import re
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin, urlsplit

import requests


ENDPOINT_RE = re.compile(
    r"(?P<quote>['\"])(?P<path>/(?:api|graphql|admin|auth|login|flag|static|assets|upload|download|debug)[^'\"\s]{0,240})(?P=quote)",
    re.IGNORECASE,
)


def origin(url):
    parsed = urlsplit(url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ValueError("URL must use http:// or https:// and contain a host")
    if parsed.username or parsed.password or parsed.fragment:
        raise ValueError("credentials and fragments are not allowed")
    host = f"[{parsed.hostname}]" if ":" in parsed.hostname else parsed.hostname
    port = f":{parsed.port}" if parsed.port is not None else ""
    return f"{parsed.scheme.lower()}://{host.lower()}{port}"


class SurfaceParser(HTMLParser):
    def __init__(self, base_url, scope_origin):
        super().__init__(convert_charrefs=True)
        self.base_url = base_url
        self.scope_origin = scope_origin
        self.forms = []
        self.links = set()
        self.scripts = set()
        self._form = None

    def scoped(self, value):
        if not value or value.startswith(("javascript:", "data:", "mailto:")):
            return None
        url = urljoin(self.base_url, value)
        try:
            return url if origin(url) == self.scope_origin else None
        except ValueError:
            return None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "form":
            self._form = {
                "method": attrs.get("method", "GET").upper(),
                "action": self.scoped(attrs.get("action", "")) or self.base_url,
                "inputs": [],
            }
            self.forms.append(self._form)
        elif tag in {"input", "textarea", "select", "button"} and self._form is not None:
            name = attrs.get("name")
            if name:
                self._form["inputs"].append({"name": name, "type": attrs.get("type", tag)})
        elif tag == "a":
            if url := self.scoped(attrs.get("href")):
                self.links.add(url)
        elif tag == "script":
            if url := self.scoped(attrs.get("src")):
                self.scripts.add(url)

    def handle_endtag(self, tag):
        if tag == "form":
            self._form = None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("url")
    parser.add_argument("--scope-origin", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--body")
    parser.add_argument("--timeout", type=float, default=8.0)
    parser.add_argument("--max-bytes", type=int, default=2_000_000)
    args = parser.parse_args()

    scope = origin(args.scope_origin)
    if origin(args.url) != scope:
        raise SystemExit("entry URL is outside --scope-origin")

    session = requests.Session()
    session.trust_env = False
    response = session.get(
        args.url,
        headers={"User-Agent": "ctf-web-blackbox-probe/1.0"},
        timeout=args.timeout,
        allow_redirects=False,
        stream=True,
    )
    data = bytearray()
    for chunk in response.iter_content(65536):
        data.extend(chunk)
        if len(data) > args.max_bytes:
            raise SystemExit(f"response exceeded {args.max_bytes} bytes")
    body = bytes(data)
    text = body.decode(response.encoding or "utf-8", errors="replace")

    surface = SurfaceParser(args.url, scope)
    if "html" in response.headers.get("Content-Type", "").lower() or "<html" in text[:1000].lower():
        surface.feed(text)

    location = response.headers.get("Location")
    redirect = None
    if location:
        candidate = urljoin(args.url, location)
        redirect = {"url": candidate, "same_origin": origin(candidate) == scope}

    result = {
        "entry_url": args.url,
        "scope_origin": scope,
        "status": response.status_code,
        "content_type": response.headers.get("Content-Type"),
        "content_length": len(body),
        "headers": {
            name: response.headers[name]
            for name in ("Server", "X-Powered-By", "Content-Security-Policy", "Allow")
            if name in response.headers
        },
        "cookie_names": sorted(response.cookies.keys()),
        "redirect": redirect,
        "forms": surface.forms[:32],
        "same_origin_links": sorted(surface.links)[:64],
        "same_origin_scripts": sorted(surface.scripts)[:32],
        "inline_endpoint_hints": sorted({m.group("path") for m in ENDPOINT_RE.finditer(text)})[:64],
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.body:
        body_path = Path(args.body)
        body_path.parent.mkdir(parents=True, exist_ok=True)
        body_path.write_bytes(body)
    print(output)


if __name__ == "__main__":
    main()
