#!/usr/bin/env python3
"""Build a compact Codex-only versus Claude-to-Codex comparison report."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def load(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def usage(paths: list[Path]) -> tuple[int | None, float, int]:
    rows = [load(path) for path in paths if path.exists()]
    values = [row.get("total_tokens") for row in rows]
    total = sum(values) if values and all(isinstance(value, int) for value in values) else None
    seconds = sum(float(row.get("duration_seconds") or 0) for row in rows)
    return total, seconds, len(rows)


def fmt_seconds(value: float) -> str:
    whole = int(value)
    hours, remainder = divmod(whole, 3600)
    minutes, seconds = divmod(remainder, 60)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}"


def success(work: Path, log: Path) -> str:
    marker = work / ".solved"
    if marker.exists() and marker.read_text(encoding="utf-8", errors="replace").strip() == "verified":
        return "성공(검증됨)"
    text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
    return "후보 출력" if re.search(r"(?m)^FLAG=", text) else "실패/미완료"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--category", required=True)
    parser.add_argument("--challenge", required=True)
    parser.add_argument("--plain-work", required=True, type=Path)
    parser.add_argument("--claude-work", required=True, type=Path)
    parser.add_argument("--plain-log", required=True, type=Path)
    parser.add_argument("--claude-log", required=True, type=Path)
    parser.add_argument("--plain-wall", required=True, type=float)
    parser.add_argument("--claude-wall", required=True, type=float)
    parser.add_argument("--plain-status", required=True, type=int)
    parser.add_argument("--claude-status", required=True, type=int)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    plain_tokens, plain_stage, plain_runs = usage([args.plain_work / "compare-codex-usage.json"])
    claude_files = sorted(args.claude_work.glob("claude-usage-*.json"))
    codex_files = sorted(args.claude_work.glob("codex-usage-*.json"))
    claude_tokens, claude_stage, claude_runs = usage(claude_files)
    mixed_codex_tokens, mixed_codex_stage, mixed_codex_runs = usage(codex_files)
    mixed_tokens = None if claude_tokens is None or mixed_codex_tokens is None else claude_tokens + mixed_codex_tokens

    token = lambda value: "미집계" if value is None else f"{value:,}"
    lines = [
        f"# {args.category} 비교 — {args.challenge}", "",
        "| 방식 | 결과 | 종료 | 전체 시간 | 단계 시간 | 토큰 | 실행 구성 |",
        "|---|---:|---:|---:|---:|---:|---|",
        f"| Codex 단독 | {success(args.plain_work, args.plain_log)} | {args.plain_status} | {fmt_seconds(args.plain_wall)} | {fmt_seconds(plain_stage)} | {token(plain_tokens)} | Codex {plain_runs}회 |",
        f"| Claude→Codex | {success(args.claude_work, args.claude_log)} | {args.claude_status} | {fmt_seconds(args.claude_wall)} | {fmt_seconds(claude_stage + mixed_codex_stage)} | {token(mixed_tokens)} | Claude {claude_runs}회 + Codex {mixed_codex_runs}회 |",
        "",
        "- 전체 시간은 준비·Docker·정리 시간을 포함합니다.",
        "- 토큰은 완료 usage 이벤트가 있는 실행만 정확히 집계되며, 중단된 턴은 미집계입니다.",
        "- 두 방식은 같은 원본에서 만든 서로 다른 작업공간을 순차 실행합니다.",
    ]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
