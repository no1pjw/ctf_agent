#!/usr/bin/env python3
"""Render Claude stream-json events and persist handoff plus usage."""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path
from typing import Any


def number(value: Any) -> int:
    return int(value or 0) if isinstance(value, (int, float)) else 0


def compact(value: Any, limit: int = 500) -> str:
    text = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    return text if len(text) <= limit else text[:limit] + "…"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--events", required=True)
    parser.add_argument("--handoff", required=True)
    parser.add_argument("--summary", required=True)
    parser.add_argument("--refusal-marker")
    parser.add_argument("--partial-ok", action="store_true")
    args = parser.parse_args()

    started = time.monotonic()
    final_result = ""
    final_usage: dict[str, Any] = {}
    observed_usage = {
        "input_tokens": 0,
        "cache_creation_input_tokens": 0,
        "cache_read_input_tokens": 0,
        "output_tokens": 0,
    }
    transcript_parts: list[str] = []
    reported_duration_ms = 0
    cost_usd: Any = None
    events_path = Path(args.events)
    events_path.parent.mkdir(parents=True, exist_ok=True)

    with events_path.open("w", encoding="utf-8") as event_file:
        for raw in sys.stdin:
            event_file.write(raw)
            event_file.flush()
            try:
                event = json.loads(raw)
            except json.JSONDecodeError:
                continue

            event_type = event.get("type")
            if event_type == "assistant":
                message = event.get("message") if isinstance(event.get("message"), dict) else {}
                message_usage = message.get("usage") if isinstance(message.get("usage"), dict) else {}
                for key in observed_usage:
                    observed_usage[key] += number(message_usage.get(key))
                content = message.get("content") if isinstance(message.get("content"), list) else []
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    block_type = block.get("type")
                    if block_type in {"text", "thinking"}:
                        text = str(block.get("text", block.get("thinking", ""))).strip()
                        if text:
                            transcript_parts.append(text)
                            label = "Claude" if block_type == "text" else "Claude 추론"
                            print(f"\n[{label}] {text}", flush=True)
                    elif block_type == "tool_use":
                        transcript_parts.append(
                            f"도구 {block.get('name', 'unknown')}: {compact(block.get('input', {}), 1000)}"
                        )
                        print(
                            f"\n[Claude 도구] {block.get('name', 'unknown')} "
                            f"{compact(block.get('input', {}))}",
                            flush=True,
                        )
            elif event_type == "user":
                message = event.get("message") if isinstance(event.get("message"), dict) else {}
                content = message.get("content") if isinstance(message.get("content"), list) else []
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "tool_result":
                        result = str(block.get("content", "")).strip()
                        if result:
                            if len(result) > 1200:
                                result = result[:1200] + "\n…[도구 출력 생략]"
                            print(f"[Claude 도구 결과]\n{result}", flush=True)
            elif event_type == "result":
                final_result = str(event.get("result", "")).strip()
                final_usage = event.get("usage") if isinstance(event.get("usage"), dict) else {}
                reported_duration_ms = number(event.get("duration_ms"))
                cost_usd = event.get("total_cost_usd")

    partial = not final_result
    if partial:
        if not transcript_parts:
            print("Claude 스트림에 handoff로 사용할 분석 내용이 없습니다.", file=sys.stderr)
            return 74
        final_result = (
            "# 제한 시간 부분 handoff\n\n"
            "Claude가 제한 시간 안에 최종 응답을 완성하지 못했다. "
            "아래 관찰은 미검증 상태이므로 Codex가 직접 확인해야 한다.\n\n"
            + "\n\n".join(transcript_parts)
        )
        final_usage = observed_usage

    Path(args.handoff).write_text(final_result + "\n", encoding="utf-8")
    refusal = bool(re.search(r"(?i)(i can(?:not|'t) continue this task|safety classifier|not able to retry|i can(?:not|'t) assist)", final_result))
    if refusal and args.refusal_marker:
        Path(args.refusal_marker).write_text("refused\n", encoding="utf-8")
    input_tokens = number(final_usage.get("input_tokens"))
    cache_creation = number(final_usage.get("cache_creation_input_tokens"))
    cache_read = number(final_usage.get("cache_read_input_tokens"))
    output_tokens = number(final_usage.get("output_tokens"))
    elapsed = reported_duration_ms / 1000 if reported_duration_ms else time.monotonic() - started
    summary = {
        "input_tokens": input_tokens,
        "cache_creation_input_tokens": cache_creation,
        "cache_read_input_tokens": cache_read,
        "output_tokens": output_tokens,
        "total_tokens": input_tokens + cache_creation + cache_read + output_tokens,
        "duration_seconds": elapsed,
        "cost_usd": cost_usd,
        "refused": refusal,
    }
    Path(args.summary).write_text(json.dumps(summary, ensure_ascii=False) + "\n", encoding="utf-8")
    completion_label = "Claude 거절" if refusal else ("Claude 부분 handoff" if partial else "Claude 완료")
    print(
        f"\n[{completion_label}] {elapsed:.3f}초, 토큰 {summary['total_tokens']:,}",
        flush=True,
    )
    return 0 if not partial or args.partial_ok else 74


if __name__ == "__main__":
    raise SystemExit(main())
