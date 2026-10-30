#!/usr/bin/env python3
"""Validate and redact a generated CTF write-up before publishing it."""

from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
from pathlib import Path


MAX_BYTES = 512 * 1024
ANSI_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
FLAG_RE = re.compile(r"(?<![A-Za-z0-9_])([A-Za-z][A-Za-z0-9_]{0,31})\{[^{}\r\n]{1,512}\}")
FLAG_LINE_RE = re.compile(r"(?im)\bFLAG\s*=\s*(?!<REDACTED>)[^\s`]+")
GITHUB_TOKEN_RE = re.compile(r"\bgh[pousr]_[A-Za-z0-9_]{20,}\b")
API_KEY_RE = re.compile(r"\bsk-(?:proj-|ant-)?[A-Za-z0-9_-]{20,}\b")
AWS_KEY_RE = re.compile(r"\bAKIA[0-9A-Z]{16}\b")
JWT_RE = re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b")
LINUX_HOME_RE = re.compile(r"(?<![A-Za-z0-9_.-])/home/[^/\s`]+")
WSL_USER_RE = re.compile(r"(?i)(?<![A-Za-z0-9_.-])/mnt/([a-z])/Users/[^/\s`]+")
WINDOWS_USER_RE = re.compile(r"(?i)\b([A-Z]:\\Users\\)[^\\\s`]+")


def read_text(path: str) -> str:
    if path == "-":
        data = sys.stdin.buffer.read(MAX_BYTES + 1)
    else:
        data = Path(path).read_bytes()
    if len(data) > MAX_BYTES:
        raise ValueError(f"draft exceeds {MAX_BYTES} bytes")
    return data.decode("utf-8", errors="replace")


def unwrap_markdown_fence(text: str) -> str:
    stripped = text.strip()
    match = re.fullmatch(r"```(?:markdown|md)?\s*\n(.*)\n```", stripped, flags=re.DOTALL | re.IGNORECASE)
    return match.group(1).strip() if match else stripped


def secret_values(paths: list[str]) -> list[str]:
    values: list[str] = []
    for raw_path in paths:
        path = Path(raw_path)
        if not path.is_file():
            continue
        if path.stat().st_size > 64 * 1024:
            continue
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            value = line.strip()
            if value.upper().startswith("FLAG="):
                value = value.split("=", 1)[1].strip()
            if 4 <= len(value) <= 1024 and value.lower() != "verified":
                values.append(value)
    return sorted(set(values), key=len, reverse=True)


def sanitize(text: str, secrets: list[str], redacted_paths: list[str]) -> str:
    text = unwrap_markdown_fence(ANSI_RE.sub("", text.replace("\x00", "")))
    text = text.replace("\r\n", "\n").replace("\r", "\n")

    for secret in secrets:
        text = text.replace(secret, "<REDACTED>")
    for raw_path in sorted(set(redacted_paths), key=len, reverse=True):
        if raw_path:
            text = text.replace(raw_path.rstrip("/\\"), "<local-path>")

    text = GITHUB_TOKEN_RE.sub("<REDACTED_GITHUB_TOKEN>", text)
    text = API_KEY_RE.sub("<REDACTED_API_KEY>", text)
    text = AWS_KEY_RE.sub("<REDACTED_AWS_KEY>", text)
    text = JWT_RE.sub("<REDACTED_JWT>", text)
    text = FLAG_RE.sub(lambda match: f"{match.group(1)}{{REDACTED}}", text)
    text = FLAG_LINE_RE.sub("FLAG=<REDACTED>", text)
    text = LINUX_HOME_RE.sub("/home/<user>", text)
    text = WSL_USER_RE.sub(lambda match: f"/mnt/{match.group(1).lower()}/Users/<user>", text)
    text = WINDOWS_USER_RE.sub(lambda match: f"{match.group(1)}<user>", text)
    return text.strip() + "\n"


def validate(text: str) -> None:
    encoded = text.encode("utf-8")
    if len(encoded) < 120:
        raise ValueError("write-up is too short")
    if len(encoded) > MAX_BYTES:
        raise ValueError(f"write-up exceeds {MAX_BYTES} bytes")
    if not re.search(r"(?m)^#\s+\S", text):
        raise ValueError("write-up needs a level-1 Markdown title")
    if re.search(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", text):
        raise ValueError("write-up contains control characters")


def write_atomic(path: str, text: str) -> None:
    if path == "-":
        sys.stdout.write(text)
        return
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{destination.name}.", dir=destination.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        os.chmod(temporary_name, 0o644)
        os.replace(temporary_name, destination)
    finally:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default="-")
    parser.add_argument("--output", default="-")
    parser.add_argument("--secret-file", action="append", default=[])
    parser.add_argument("--redact-path", action="append", default=[])
    args = parser.parse_args()
    try:
        cleaned = sanitize(
            read_text(args.input),
            secret_values(args.secret_file),
            args.redact_path,
        )
        validate(cleaned)
        write_atomic(args.output, cleaned)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"write-up validation failed: {error}", file=sys.stderr)
        return 65
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
