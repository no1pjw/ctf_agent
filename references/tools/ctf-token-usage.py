#!/usr/bin/env python3
"""Render Codex JSONL output and print exact per-run token usage."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--suppress-agent-messages", action="store_true")
    parser.add_argument("--events")
    parser.add_argument("--summary", default=os.environ.get("CTF_USAGE_SUMMARY_FILE"))
    args = parser.parse_args()
    started = time.monotonic()

    totals = {key: 0 for key in (
        "input_tokens", "cached_input_tokens", "output_tokens",
        "reasoning_output_tokens",
    )}
    usage_events = 0
    interrupted = False
    event_file = Path(args.events).open("w", encoding="utf-8") if args.events else None
    try:
        for raw in sys.stdin:
            if event_file:
                event_file.write(raw)
                event_file.flush()
            try:
                event = json.loads(raw)
            except json.JSONDecodeError:
                if args.verbose:
                    print(raw, end="", flush=True)
                continue

            if event.get("type") == "turn.completed" and isinstance(event.get("usage"), dict):
                usage_events += 1
                usage = event["usage"]
                for key in totals:
                    totals[key] += int(usage.get(key, 0) or 0)

            if event.get("type") != "item.completed":
                continue
            item = event.get("item") if isinstance(event.get("item"), dict) else {}
            item_type = item.get("type")
            if item_type == "agent_message":
                text = str(item.get("text", "")).strip()
                if text and not args.suppress_agent_messages:
                    print(text, flush=True)
            elif args.verbose and item_type == "command_execution":
                command = str(item.get("command", "")).strip()
                output = str(item.get("aggregated_output", "")).rstrip()
                if command:
                    print(f"\n$ {command}", flush=True)
                if output:
                    print(output, flush=True)
            elif item_type == "command_execution":
                output = str(item.get("aggregated_output", ""))
                for line in output.splitlines():
                    if line.startswith("FLAG=") or line.startswith("BLOCKED="):
                        print(line, flush=True)
            elif args.verbose and item_type == "reasoning":
                text = str(item.get("text", item.get("summary", ""))).strip()
                if text:
                    print(f"\n[reasoning] {text}", flush=True)
    except KeyboardInterrupt:
        interrupted = True
    finally:
        if event_file:
            event_file.close()

    elapsed = time.monotonic() - started
    elapsed_seconds = int(elapsed)
    hours, remainder = divmod(elapsed_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    print(
        f"총 소요 시간: {hours:02d}:{minutes:02d}:{seconds:02d} "
        f"({elapsed:.3f}초)",
        flush=True,
    )

    if usage_events:
        total = totals["input_tokens"] + totals["output_tokens"]
        uncached_input = max(0, totals["input_tokens"] - totals["cached_input_tokens"])
        uncached_total = uncached_input + totals["output_tokens"]
        print(
            "토큰 사용량: "
            f"입력 {totals['input_tokens']:,} "
            f"(캐시 {totals['cached_input_tokens']:,}, 새 입력 {uncached_input:,}), "
            f"출력 {totals['output_tokens']:,} "
            f"(추론 {totals['reasoning_output_tokens']:,}), "
            f"누적 합계 {total:,}, 비캐시 처리량 {uncached_total:,}",
            flush=True,
        )
    else:
        print("토큰 사용량: 미집계 (turn.completed.usage 없음)", flush=True)
    if args.summary:
        summary = {
            **totals,
            "total_tokens": totals["input_tokens"] + totals["output_tokens"] if usage_events else None,
            "uncached_input_tokens": max(0, totals["input_tokens"] - totals["cached_input_tokens"]) if usage_events else None,
            "uncached_total_tokens": max(0, totals["input_tokens"] - totals["cached_input_tokens"]) + totals["output_tokens"] if usage_events else None,
            "usage_events": usage_events,
            "duration_seconds": elapsed,
        }
        destination = Path(args.summary)
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(destination.name + ".tmp")
        temporary.write_text(json.dumps(summary, ensure_ascii=False) + "\n", encoding="utf-8")
        temporary.replace(destination)
    return 130 if interrupted else 0


if __name__ == "__main__":
    raise SystemExit(main())
