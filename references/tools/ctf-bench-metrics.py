#!/usr/bin/env python3
"""Stream and summarize ctf-bench Codex JSONL events."""

from __future__ import annotations

import argparse
import json
import re
import select
import sys
import time
import unicodedata
from pathlib import Path
from collections.abc import Iterator
from typing import Any


FLAG_TOKEN = r"[A-Za-z][A-Za-z0-9_]{0,31}\{[^{}\r\n]{1,256}\}"
FLAG_RE = re.compile(rf"\b{FLAG_TOKEN}")
REMOTE_HARNESS_MARKER_RE = re.compile(
    rf"(?m)^[ \t]*획득한 플래그:[ \t]*({FLAG_TOKEN})[ \t]*$"
)
REMOTE_FLAG_EXIT = 10
TOOL_ITEM_TYPES = {
    "command_execution",
    "computer_use",
    "file_change",
    "mcp_tool_call",
    "web_search",
}
SUBAGENT_TOOL_NAMES = (
    "spawn_agent",
    "send_input",
    "resume_agent",
    "wait_agent",
    "close_agent",
    "send_message",
    "followup_task",
)


def observable_output(event: dict[str, Any]) -> str:
    """Return only model/output text, never commands, prompts, or source payloads."""
    if event.get("type") != "item.completed":
        return ""
    item = event.get("item") if isinstance(event.get("item"), dict) else {}
    if item.get("type") == "agent_message":
        return str(item.get("text", ""))
    if item.get("type") == "command_execution":
        return str(item.get("aggregated_output", ""))
    return ""


def first_valid_flag(text: str) -> str | None:
    for match in FLAG_RE.finditer(text):
        candidate = match.group(0)
        body = candidate[candidate.index("{") + 1 : -1].strip()
        if body not in {"...", "…", "<flag>", "flag", "원문"}:
            return candidate
    return None


def remote_flag_from_event(event: dict[str, Any]) -> str | None:
    """Accept only the bounded remote harness proof from command output."""
    if event.get("type") != "item.completed":
        return None
    item = event.get("item") if isinstance(event.get("item"), dict) else {}
    text = observable_output(event)
    if item.get("type") != "command_execution":
        return None
    command = str(item.get("command", ""))
    if "pwn-remote-run.sh" not in command and "CTF_REMOTE_HARNESS" not in command:
        return None
    match = REMOTE_HARNESS_MARKER_RE.search(text)
    if not match:
        return None
    candidate = match.group(1)
    return candidate if first_valid_flag(candidate) == candidate else None


def read_jsonl(path: Path) -> Iterator[dict[str, Any]]:
    """Stream events so a long xhigh run never loads the JSONL into RAM."""
    if not path.exists():
        return
    with path.open(encoding="utf-8", errors="replace") as stream:
        for line in stream:
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(value, dict):
                yield value


def compact_event(event: dict[str, Any]) -> dict[str, Any]:
    """Keep metrics evidence while bounding verbose reasoning/tool payloads."""
    compact = dict(event)
    item = compact.get("item")
    if not isinstance(item, dict):
        return compact
    item = dict(item)
    compact["item"] = item
    item_type = item.get("type")
    if item_type == "reasoning":
        for key in ("text", "content", "summary"):
            if key in item:
                item[key] = "[reasoning omitted from benchmark log]"
    if item_type == "command_execution":
        output = str(item.get("aggregated_output", ""))
        limit = 65536
        if len(output) > limit:
            item["aggregated_output"] = (
                output[: limit // 2]
                + f"\n[... {len(output) - limit} characters omitted ...]\n"
                + output[-limit // 2 :]
            )
    return compact


def action_label(command: str) -> str:
    text = " ".join(command.split()).lower()
    if "pwn-remote-run.sh" in text or "ctf_remote_harness" in text:
        return "원격 exploit 실행"
    if "docker build" in text or "pwn-build.sh" in text:
        return "Docker 환경 빌드"
    if "docker run" in text or "pwn-run.sh" in text:
        return "격리 로컬 exploit 실행"
    if "gdb" in text:
        return "GDB 동적 분석"
    if any(tool in text for tool in ("checksec", "readelf", "objdump", "ropgadget", "ropper", "nm ")):
        return "바이너리·가젯 정적 분석"
    if any(tool in text for tool in ("rg ", "grep ", "find ", "strings ")):
        return "파일·문자열 조사"
    if "py_compile" in text:
        return "solver 문법 검사"
    if "python" in text or "solve.py" in text:
        return "분석·solver 실행"
    return "도구 실행"


def read_status(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    if not path.exists():
        return result
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        key, separator, value = line.partition("=")
        if separator:
            result[key] = value
    return result


def command_capture(args: argparse.Namespace) -> int:
    started = time.monotonic()
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    first_flag_seen = False
    remote_flag_seen = False
    usage_deadline: float | None = None
    active_actions: dict[str, str] = {}

    with output.open("w", encoding="utf-8", newline="\n") as handle:
        while True:
            wait_seconds: float | None = None
            if usage_deadline is not None:
                wait_seconds = max(0.0, usage_deadline - time.monotonic())
                if wait_seconds == 0.0:
                    return REMOTE_FLAG_EXIT

            readable, _, _ = select.select([sys.stdin], [], [], wait_seconds)
            if not readable:
                return REMOTE_FLAG_EXIT if remote_flag_seen else 0

            raw = sys.stdin.readline()
            if raw == "":
                return REMOTE_FLAG_EXIT if remote_flag_seen else 0

            elapsed = round(time.monotonic() - started, 3)
            try:
                event = json.loads(raw)
            except json.JSONDecodeError:
                event = {"type": "benchmark.unparsed", "text": raw.rstrip("\r\n")}
            if not isinstance(event, dict):
                event = {"type": "benchmark.unparsed", "value": event}
            event["_benchmark_elapsed_seconds"] = elapsed

            combined = observable_output(event)
            remote_flag = remote_flag_from_event(event) if args.stop_on_flag else None
            if remote_flag:
                event["_benchmark_remote_flag"] = remote_flag
                event["_benchmark_remote_flag_seconds"] = elapsed

            handle.write(json.dumps(compact_event(event), ensure_ascii=False, separators=(",", ":")) + "\n")
            handle.flush()

            candidate = first_valid_flag(combined)
            if candidate and not first_flag_seen:
                first_flag_seen = True
                if not args.quiet:
                    print(f"[{args.label} +{elapsed:.1f}s] 첫 플래그 후보: {candidate}", flush=True)
            event_type = event.get("type")
            item = event.get("item") if isinstance(event.get("item"), dict) else {}
            if not args.quiet and event_type == "thread.started":
                print(f"[{args.label}] Codex exec 연결 완료", flush=True)
            elif not args.quiet and event_type == "item.started" and item.get("type") == "command_execution":
                action = action_label(str(item.get("command", "")))
                active_actions[str(item.get("id", ""))] = action
                print(f"[{args.label} +{elapsed:.1f}s] 행동: {action}", flush=True)
            elif not args.quiet and event_type == "item.completed" and item.get("type") == "command_execution":
                action = active_actions.pop(str(item.get("id", "")), action_label(str(item.get("command", ""))))
                exit_code = item.get("exit_code")
                if isinstance(exit_code, int) and exit_code != 0:
                    print(f"[{args.label} +{elapsed:.1f}s] 결과: {action} 실패 (exit {exit_code})", flush=True)
            elif not args.quiet and event_type == "item.completed" and item.get("type") == "file_change":
                print(f"[{args.label} +{elapsed:.1f}s] 행동: solver 또는 작업 파일 수정", flush=True)
            elif not args.quiet and event_type == "item.completed" and item.get("type") == "agent_message":
                text = str(item.get("text", "")).replace("\n", " ").strip()
                if text:
                    print(f"[{args.label} +{elapsed:.1f}s] 판단: {text[:240]}", flush=True)
            if remote_flag:
                remote_flag_seen = True
                if not args.quiet:
                    print(
                        f"[{args.label} +{elapsed:.1f}s] 원격 플래그 포착, 즉시 종료",
                        flush=True,
                    )
                if args.usage_grace <= 0:
                    return REMOTE_FLAG_EXIT
                usage_deadline = time.monotonic() + args.usage_grace
                continue

            if remote_flag_seen:
                if event_type == "turn.completed":
                    return REMOTE_FLAG_EXIT
                if event_type == "item.started" and item.get("type") in TOOL_ITEM_TYPES:
                    # Token telemetry must never permit post-flag verification or
                    # another remote attempt. End immediately if a new tool starts.
                    return REMOTE_FLAG_EXIT


def command_summarize(args: argparse.Namespace) -> int:
    events = read_jsonl(Path(args.events))
    status = read_status(Path(args.status))
    input_tokens = 0
    cached_input_tokens = 0
    output_tokens = 0
    reasoning_output_tokens = 0
    tool_calls = 0
    subagent_event_ids: set[str] = set()
    first_flag_seconds: float | None = None
    first_flag: str | None = None
    remote_flag_seconds: float | None = None
    remote_flag: str | None = None
    usage_events = 0

    for event in events:
        if remote_flag is None and isinstance(event.get("_benchmark_remote_flag"), str):
            remote_flag = event["_benchmark_remote_flag"]
            elapsed = event.get("_benchmark_remote_flag_seconds")
            if isinstance(elapsed, (int, float)):
                remote_flag_seconds = float(elapsed)

        if event.get("type") == "turn.completed" and isinstance(event.get("usage"), dict):
            usage_events += 1
            usage = event["usage"]
            input_tokens += int(usage.get("input_tokens", 0) or 0)
            cached_input_tokens += int(usage.get("cached_input_tokens", 0) or 0)
            output_tokens += int(usage.get("output_tokens", 0) or 0)
            reasoning_output_tokens += int(usage.get("reasoning_output_tokens", 0) or 0)

        item = event.get("item") if isinstance(event.get("item"), dict) else {}
        if event.get("type") == "item.completed" and item.get("type") in TOOL_ITEM_TYPES:
            tool_calls += 1

        item_type = str(item.get("type", "")).lower()
        tool_name = str(
            item.get("tool_name", item.get("name", item.get("tool", "")))
        ).lower()
        is_subagent_event = (
            "collab" in item_type
            or "subagent" in item_type
            or tool_name in SUBAGENT_TOOL_NAMES
        )
        if is_subagent_event:
            event_id = str(item.get("id", "")) or json.dumps(item, ensure_ascii=False, sort_keys=True)
            subagent_event_ids.add(event_id)

        if first_flag is None:
            candidate = first_valid_flag(observable_output(event))
            if candidate:
                first_flag = candidate
                elapsed = event.get("_benchmark_elapsed_seconds")
                if isinstance(elapsed, (int, float)):
                    first_flag_seconds = float(elapsed)

    work_dir = Path(args.work_dir)
    solved_file = work_dir / ".solved"
    verified = solved_file.exists() and solved_file.read_text(
        encoding="utf-8", errors="replace"
    ).strip() == "verified"
    exit_status = int(status.get("exit_status", "255"))
    capture_status = int(status.get("capture_status", "255"))
    duration_ms = int(status.get("duration_ms", "0"))
    subagent_events = len(subagent_event_ids)
    remote_mode = status.get("remote_mode") == "true"
    flag_short_circuit = status.get("flag_short_circuit") == "true"
    if remote_mode:
        # In a timed CTF benchmark, an explicitly marked flag from the authorized
        # remote endpoint is the terminal success condition. Exit/replay/writeup
        # status is intentionally ignored after that marker.
        success = remote_flag is not None
    else:
        success = exit_status == 0 and capture_status == 0 and verified and subagent_events == 0

    summary = {
        "key": args.key,
        "label": args.label,
        "success": success,
        "remote_mode": remote_mode,
        "remote_flag": remote_flag,
        "remote_flag_seconds": remote_flag_seconds,
        "flag_short_circuit": flag_short_circuit,
        "verified": verified,
        "exit_status": exit_status,
        "capture_status": capture_status,
        "timed_out": status.get("timed_out") == "true",
        "duration_seconds": round(duration_ms / 1000, 3),
        "first_flag_seconds": first_flag_seconds,
        "first_flag": first_flag,
        "input_tokens": input_tokens,
        "cached_input_tokens": cached_input_tokens,
        "output_tokens": output_tokens,
        "reasoning_output_tokens": reasoning_output_tokens,
        "total_tokens": input_tokens + output_tokens if usage_events else None,
        "token_usage_available": usage_events > 0,
        "token_usage_events": usage_events,
        "tool_calls": tool_calls,
        "subagent_events": subagent_events,
        "events_file": str(Path(args.events)),
        "work_dir": str(work_dir),
    }
    Path(args.output).write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return 0


def display_success(summary: dict[str, Any]) -> str:
    if summary.get("success"):
        if summary.get("remote_mode"):
            return "성공 (원격 플래그)"
        return "통과 (clean replay)"
    if summary.get("remote_mode"):
        if summary.get("timed_out"):
            return "실패 (시간 초과)"
        return "실패 (원격 플래그 없음)"
    if summary.get("subagent_events", 0):
        return "실패 (서브에이전트 감지)"
    if summary.get("timed_out"):
        return "실패 (시간 초과)"
    if not summary.get("verified"):
        return "실패 (.solved 미검증)"
    return f"실패 (exit {summary.get('exit_status')})"


def seconds(value: Any) -> str:
    return "-" if value is None else f"{float(value):.1f}초"


def display_tokens(summary: dict[str, Any]) -> str:
    usage_available = summary.get("token_usage_available")
    if usage_available is None:
        usage_available = isinstance(summary.get("total_tokens"), int)
    if not usage_available:
        return "미집계 (즉시 종료)"
    return f"{int(summary.get('total_tokens', 0)):,}"


def display_width(value: Any) -> int:
    """Return terminal cell width without depending on locale-specific wcwidth."""
    width = 0
    for character in str(value):
        if unicodedata.combining(character):
            continue
        width += 2 if unicodedata.east_asian_width(character) in {"W", "F"} else 1
    return width


def pad_cell(value: Any, width: int) -> str:
    text = str(value)
    return text + " " * max(0, width - display_width(text))


def terminal_table(headers: tuple[str, ...], rows: list[tuple[str, ...]]) -> str:
    widths = [display_width(header) for header in headers]
    for row in rows:
        for index, value in enumerate(row):
            widths[index] = max(widths[index], display_width(value))

    def border(left: str, middle: str, right: str) -> str:
        return left + middle.join("─" * (width + 2) for width in widths) + right

    def content(row: tuple[str, ...]) -> str:
        cells = (pad_cell(value, widths[index]) for index, value in enumerate(row))
        return "│ " + " │ ".join(cells) + " │"

    lines = [border("┌", "┬", "┐"), content(headers), border("├", "┼", "┤")]
    lines.extend(content(row) for row in rows)
    lines.append(border("└", "┴", "┘"))
    return "\n".join(lines)


def markdown_cell(value: Any) -> str:
    return str(value).replace("|", "\\|")


def command_report(args: argparse.Namespace) -> int:
    plain = json.loads(Path(args.plain).read_text(encoding="utf-8"))
    fast = json.loads(Path(args.fast).read_text(encoding="utf-8"))
    remote_mode = bool(plain.get("remote_mode") or fast.get("remote_mode"))
    flag_time_label = "원격 플래그 시간" if remote_mode else "첫 플래그 후보"
    plain_flag_time = plain.get("remote_flag_seconds") if remote_mode else plain.get("first_flag_seconds")
    fast_flag_time = fast.get("remote_flag_seconds") if remote_mode else fast.get("first_flag_seconds")
    plain_solve_time = plain_flag_time if remote_mode and plain_flag_time is not None else plain["duration_seconds"]
    fast_solve_time = fast_flag_time if remote_mode and fast_flag_time is not None else fast["duration_seconds"]
    rows = [
        ("성공", display_success(plain), display_success(fast)),
        ("풀이 시간", seconds(plain_solve_time), seconds(fast_solve_time)),
        (flag_time_label, seconds(plain_flag_time), seconds(fast_flag_time)),
        ("총 토큰", display_tokens(plain), display_tokens(fast)),
        ("도구 호출", f"{plain['tool_calls']}회", f"{fast['tool_calls']}회"),
        ("서브에이전트 이벤트", f"{plain['subagent_events']}회", f"{fast['subagent_events']}회"),
    ]
    lines = [
        "# CTF Benchmark",
        "",
        "| 지표 | plain Codex | FAST_LOCAL |",
        "| --- | ---: | ---: |",
    ]
    lines.extend(
        f"| {markdown_cell(metric)} | {markdown_cell(plain_value)} | {markdown_cell(fast_value)} |"
        for metric, plain_value, fast_value in rows
    )
    if remote_mode:
        lines.extend(
            [
                f"| 획득한 원격 플래그 | {markdown_cell(plain.get('remote_flag') or '-')} | {markdown_cell(fast.get('remote_flag') or '-')} |",
            ]
        )
    lines.extend(
        [
            "",
            "## 고정 설정",
            "",
            "- Model: `gpt-5.6-sol`",
            "- Reasoning effort: `xhigh`",
            "- Service tier: `fast`",
            "- Multi-agent: disabled",
            "- Automatic skill search: disabled",
            "- User-installed skills: isolated with a temporary CODEX_HOME",
            "- Sessions: ephemeral",
            "- Execution: plain Codex and FAST_LOCAL in parallel",
            f"- Success mode: {'bounded remote harness flag short-circuit' if remote_mode else 'local clean replay'}",
            "",
            "`총 토큰`은 Codex JSONL의 `turn.completed.usage`에서 받은 `input_tokens + output_tokens` 합계입니다.",
            "원격 플래그 시각은 즉시 고정하고, 후속 도구 실행을 금지한 채 최종 `turn.completed.usage`만 제한 시간 동안 기다립니다. usage가 끝내 오지 않으면 0으로 오표시하지 않고 `미집계`로 표시합니다. 즉시 종료가 더 중요할 때만 `--no-exact-tokens`를 사용합니다.",
            (
                "원격 모드에서는 공용 원격 하니스의 플래그 획득 증거를 포착하는 즉시 성공으로 인정하고 후속 검증을 생략합니다."
                if remote_mode
                else "성공은 정상 종료, `work/.solved=verified`, 서브에이전트 이벤트 0회를 모두 만족할 때만 인정합니다."
            ),
            (
                "원격 성공의 풀이 시간은 플래그 포착 시점이며, 토큰 수는 조기 종료 전까지 수집된 부분 합계일 수 있습니다."
                if remote_mode
                else ""
            ),
            "",
        ]
    )
    report = "\n".join(lines)
    Path(args.output).write_text(report, encoding="utf-8")
    print("\n" + terminal_table(("지표", "plain Codex", "FAST_LOCAL"), rows))
    if remote_mode:
        print("\n획득한 원격 플래그")
        print(f"  plain Codex: {plain.get('remote_flag') or '-'}")
        print(f"  FAST_LOCAL:  {fast.get('remote_flag') or '-'}")
    return 0


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    subcommands = root.add_subparsers(dest="command", required=True)

    capture = subcommands.add_parser("capture")
    capture.add_argument("--label", required=True)
    capture.add_argument("--output", required=True)
    capture.add_argument("--quiet", action="store_true")
    capture.add_argument("--stop-on-flag", action="store_true")
    capture.add_argument("--usage-grace", type=float, default=0.0)
    capture.set_defaults(function=command_capture)

    summarize = subcommands.add_parser("summarize")
    summarize.add_argument("--key", required=True)
    summarize.add_argument("--label", required=True)
    summarize.add_argument("--events", required=True)
    summarize.add_argument("--status", required=True)
    summarize.add_argument("--work-dir", required=True)
    summarize.add_argument("--output", required=True)
    summarize.set_defaults(function=command_summarize)

    report = subcommands.add_parser("report")
    report.add_argument("--plain", required=True)
    report.add_argument("--fast", required=True)
    report.add_argument("--output", required=True)
    report.set_defaults(function=command_report)
    return root


def main() -> int:
    args = parser().parse_args()
    return int(args.function(args))


if __name__ == "__main__":
    raise SystemExit(main())
