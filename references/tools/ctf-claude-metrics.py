#!/usr/bin/env python3
"""Extract Claude usage and report combined Claude + Codex metrics."""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Any


def number(value: Any) -> int:
    return int(value or 0) if isinstance(value, (int, float)) else 0


def load(path: str) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def extract(args: argparse.Namespace) -> int:
    payload = load(args.input)
    result = str(payload.get("result", "")).strip()
    if not result:
        raise SystemExit("Claude 결과에서 handoff 본문을 찾지 못했습니다.")
    Path(args.handoff).write_text(result + "\n", encoding="utf-8")

    usage = payload.get("usage") if isinstance(payload.get("usage"), dict) else {}
    input_tokens = number(usage.get("input_tokens"))
    cache_creation = number(usage.get("cache_creation_input_tokens"))
    cache_read = number(usage.get("cache_read_input_tokens"))
    output_tokens = number(usage.get("output_tokens"))
    duration_ms = number(payload.get("duration_ms"))
    summary = {
        "input_tokens": input_tokens,
        "cache_creation_input_tokens": cache_creation,
        "cache_read_input_tokens": cache_read,
        "output_tokens": output_tokens,
        "total_tokens": input_tokens + cache_creation + cache_read + output_tokens,
        "duration_seconds": duration_ms / 1000,
        "cost_usd": payload.get("total_cost_usd"),
    }
    Path(args.summary).write_text(json.dumps(summary, ensure_ascii=False) + "\n", encoding="utf-8")
    return 0


def duration(value: float) -> str:
    whole = int(value)
    hours, remainder = divmod(whole, 3600)
    minutes, seconds = divmod(remainder, 60)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d} ({value:.3f}초)"


def combined(args: argparse.Namespace) -> int:
    claude_runs = [load(path) for path in args.claude if Path(path).exists()]
    codex_runs = [load(path) for path in args.codex if Path(path).exists()]
    claude_values = [run.get("total_tokens") for run in claude_runs]
    codex_values = [run.get("total_tokens") for run in codex_runs]
    claude_total = sum(claude_values) if claude_values and all(isinstance(value, int) for value in claude_values) else None
    codex_total = sum(codex_values) if codex_values and all(isinstance(value, int) for value in codex_values) else None
    claude_seconds = sum(float(run.get("duration_seconds") or 0) for run in claude_runs)
    codex_seconds = sum(float(run.get("duration_seconds") or 0) for run in codex_runs)
    wall_seconds = max(0.0, time.time() - args.started)

    print("\nClaude → Codex 합산 사용량")
    print(f"Claude ({len(claude_runs)}회): {duration(claude_seconds)}, 토큰 {claude_total:,}" if isinstance(claude_total, int) else f"Claude ({len(claude_runs)}회): {duration(claude_seconds)}, 토큰 미집계")
    print(f"Codex  ({len(codex_runs)}회): {duration(codex_seconds)}, 토큰 {codex_total:,}" if isinstance(codex_total, int) else f"Codex  ({len(codex_runs)}회): {duration(codex_seconds)}, 토큰 미집계")
    if isinstance(claude_total, int) and isinstance(codex_total, int):
        print(f"합계:   단계 시간 {duration(claude_seconds + codex_seconds)}, 토큰 {claude_total + codex_total:,}")
    else:
        print(f"합계:   단계 시간 {duration(claude_seconds + codex_seconds)}, 토큰 미집계")
    print(f"전체 경과: {duration(wall_seconds)}")
    return 0


def claude_only(args: argparse.Namespace) -> int:
    row = load(args.summary) if Path(args.summary).exists() else {}
    seconds = float(row.get("duration_seconds") or 0)
    tokens = row.get("total_tokens")
    wall_seconds = max(0.0, time.monotonic() - args.started_monotonic)
    print("\nClaude 단독 사용량")
    print(f"Claude: {duration(seconds)}, 토큰 {tokens:,}" if isinstance(tokens, int) else f"Claude: {duration(seconds)}, 토큰 미집계")
    print(f"전체 경과: {duration(wall_seconds)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    extract_parser = sub.add_parser("extract")
    extract_parser.add_argument("--input", required=True)
    extract_parser.add_argument("--handoff", required=True)
    extract_parser.add_argument("--summary", required=True)
    extract_parser.set_defaults(function=extract)
    combined_parser = sub.add_parser("combined")
    combined_parser.add_argument("--claude", required=True, nargs="+")
    combined_parser.add_argument("--codex", required=True, nargs="+")
    combined_parser.add_argument("--started", required=True, type=float)
    combined_parser.set_defaults(function=combined)
    only_parser = sub.add_parser("claude-only")
    only_parser.add_argument("--summary", required=True)
    only_parser.add_argument("--started-monotonic", required=True, type=float)
    only_parser.set_defaults(function=claude_only)
    args = parser.parse_args()
    return args.function(args)


if __name__ == "__main__":
    raise SystemExit(main())
