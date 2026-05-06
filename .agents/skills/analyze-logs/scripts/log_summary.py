#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

PACIFIC = ZoneInfo("America/Los_Angeles")

DEFAULT_LOG = (
    "/Users/jubi/Library/Mobile Documents/"
    "com~apple~CloudDocs/PodHaven Assets/log.ndjson"
)

LEVEL_NAMES = {
    0: "trace",
    1: "debug",
    2: "info",
    3: "notice",
    4: "warning",
    5: "error",
    6: "critical",
}
LEVEL_VALUES = {name: value for value, name in LEVEL_NAMES.items()}
URL_ERROR_CODES: dict[int, tuple[str, str]] = {
    -1001: ("timedOut", "An asynchronous operation timed out."),
    -1003: ("cannotFindHost", "The system couldn't find the host."),
    -1004: ("cannotConnectToHost", "The system couldn't connect to the host."),
    -1005: ("networkConnectionLost", "The network connection was lost."),
    -1009: (
        "notConnectedToInternet",
        "A network resource was requested, but an internet connection wasn't available.",
    ),
    -1011: ("badServerResponse", "The URL Loading system received bad data from the server."),
    -1015: ("cannotDecodeRawData", "The system couldn't decode the raw response data."),
    -1016: (
        "cannotDecodeContentData",
        "The system couldn't decode the response content into the expected format.",
    ),
    -1017: ("cannotParseResponse", "A task couldn't parse the response."),
}
URL_ERROR_PATTERN = re.compile(r"NSURLErrorDomain(?:\s+error)?[^-\d]*(?P<code>-\d+)")


def parse_time_arg(s: str) -> int:
    """Parse a user-supplied time string into epoch milliseconds."""
    for fmt in (
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%d",
        "%m/%d %H:%M",
    ):
        try:
            dt = datetime.strptime(s, fmt)
            if dt.year == 1900:
                dt = dt.replace(year=datetime.now().year)
            dt = dt.replace(tzinfo=PACIFIC)
            return int(dt.timestamp() * 1000)
        except ValueError:
            continue
    try:
        return int(s)
    except ValueError:
        print(f"error: cannot parse time '{s}'", file=sys.stderr)
        sys.exit(1)


@dataclass(frozen=True)
class Entry:
    line_number: int
    level: int
    level_name: str
    timestamp_ms: int
    subsystem: str
    category: str
    message: str
    metadata: dict[str, str] | None
    source: str
    file: str
    function: str
    line: int


@dataclass
class IssueGroup:
    entry: Entry
    count: int
    first_timestamp_ms: int
    last_timestamp_ms: int
    gap_count: int = 0
    gap_sum_ms: int = 0
    min_gap_ms: int | None = None
    max_gap_ms: int | None = None

    def add(self, entry: Entry) -> None:
        gap_ms = entry.timestamp_ms - self.last_timestamp_ms
        self.count += 1
        self.last_timestamp_ms = entry.timestamp_ms
        self.gap_count += 1
        self.gap_sum_ms += gap_ms
        self.min_gap_ms = gap_ms if self.min_gap_ms is None else min(self.min_gap_ms, gap_ms)
        self.max_gap_ms = gap_ms if self.max_gap_ms is None else max(self.max_gap_ms, gap_ms)


@dataclass
class EntryBurst:
    first_entry: Entry
    last_entry: Entry
    count: int = 1


@dataclass
class Report:
    path: Path
    parse_errors: list[str]
    file_entries: list[Entry]
    active_entries: list[Entry]
    selection_entries: list[Entry]
    selection_bursts: list[EntryBurst]
    issue_groups: list[IssueGroup]
    issue_group_map: dict[tuple[Any, ...], IssueGroup]
    scope_applied: bool
    filters_applied: bool
    scope_description: str | None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Summarize PodHaven NDJSON logs and optionally filter or compare them."
    )
    parser.add_argument("path", nargs="?", default=DEFAULT_LOG, help="Path to log.ndjson or widget-log.ndjson")
    parser.add_argument(
        "--compare-other",
        help="Compare the first log file to another log file using the same scope and filters.",
    )
    parser.add_argument(
        "--min-level",
        choices=list(LEVEL_VALUES),
        help="Only include entries at or above this level in the selection view.",
    )
    parser.add_argument(
        "--around",
        type=int,
        help="Select entries within --window-ms of this timestamp in milliseconds.",
    )
    parser.add_argument(
        "--window-ms",
        type=int,
        default=30000,
        help="Window size in milliseconds for --around. Default: 30000.",
    )
    parser.add_argument(
        "--match",
        help="Case-insensitive text filter across message, metadata, and structural fields.",
    )
    parser.add_argument(
        "--subsystem",
        help="Case-insensitive subsystem filter.",
    )
    parser.add_argument(
        "--category",
        help="Case-insensitive category filter.",
    )
    parser.add_argument(
        "--source",
        help="Case-insensitive source filter.",
    )
    parser.add_argument(
        "--file",
        help="Case-insensitive source-file filter.",
    )
    parser.add_argument(
        "--function",
        help="Case-insensitive function-name filter.",
    )
    parser.add_argument(
        "--after",
        help="Only include entries after this time (datetime string or epoch ms).",
    )
    parser.add_argument(
        "--before",
        help="Only include entries before this time (datetime string or epoch ms).",
    )
    parser.add_argument(
        "--last-hours",
        type=float,
        help="Restrict the active view to entries within this many hours of the latest entry.",
    )
    parser.add_argument(
        "--tail",
        type=int,
        help="Restrict the active view to the last N entries after other scope filters are applied.",
    )
    parser.add_argument(
        "--top",
        type=int,
        default=8,
        help="Number of recurring warning/error families to show. Default: 8.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=20,
        help="Number of selected entries or bursts to print. Default: 20.",
    )
    parser.add_argument(
        "--coalesce-window-ms",
        type=int,
        default=1000,
        help=(
            "Collapse consecutive duplicate selected entries into bursts when they occur "
            "within this window. Use 0 to disable. Default: 1000."
        ),
    )
    parser.add_argument(
        "--json",
        dest="json_output",
        action="store_true",
        help="Emit machine-readable JSON instead of text.",
    )
    parser.add_argument(
        "--sessions",
        action="store_true",
        help="Detect and list app sessions (launch boundaries) with problem counts.",
    )
    return parser.parse_args()


def format_timestamp(timestamp_ms: int) -> str:
    dt = datetime.fromtimestamp(timestamp_ms / 1000, UTC).astimezone(PACIFIC)
    millis = int(timestamp_ms % 1000)
    return f"{dt:%Y-%m-%d %H:%M:%S}.{millis:03d} {dt.tzname()}"


def format_duration(duration_ms: int) -> str:
    total_seconds, millis = divmod(max(duration_ms, 0), 1000)
    minutes, seconds = divmod(total_seconds, 60)
    hours, minutes = divmod(minutes, 60)
    days, hours = divmod(hours, 24)

    parts: list[str] = []
    if days:
        parts.append(f"{days}d")
    if hours:
        parts.append(f"{hours}h")
    if minutes:
        parts.append(f"{minutes}m")
    if seconds:
        parts.append(f"{seconds}s")
    if millis and not parts:
        parts.append(f"{millis}ms")
    return " ".join(parts) if parts else "0s"


def format_counter(counter: Counter[str], limit: int | None = None) -> str:
    items = counter.most_common(limit)
    return ", ".join(f"{key}={value}" for key, value in items) if items else "none"


def indent_block(text: str, prefix: str = "    ") -> str:
    return "\n".join(f"{prefix}{line}" for line in text.splitlines()) if text else f"{prefix}<empty>"


def counter_to_dict(counter: Counter[str], limit: int | None = None) -> dict[str, int]:
    items = counter.most_common(limit)
    return {key: value for key, value in items}


def range_summary(entries: list[Entry]) -> dict[str, Any] | None:
    if not entries:
        return None

    start = min(entry.timestamp_ms for entry in entries)
    end = max(entry.timestamp_ms for entry in entries)
    return {
        "start_ms": start,
        "end_ms": end,
        "start_pt": format_timestamp(start),
        "end_pt": format_timestamp(end),
        "duration_ms": end - start,
        "duration_human": format_duration(end - start),
    }


def parse_entry(line_number: int, raw_line: str) -> Entry:
    payload: dict[str, Any] = json.loads(raw_line)
    metadata = payload.get("metadata")
    metadata_dict = dict(metadata) if isinstance(metadata, dict) else None
    level = int(payload["level"])
    level_name = str(payload.get("levelName", LEVEL_NAMES.get(level, str(level))))
    return Entry(
        line_number=line_number,
        level=level,
        level_name=level_name,
        timestamp_ms=int(payload["timestamp"]),
        subsystem=str(payload.get("subsystem", "")),
        category=str(payload.get("category", "")),
        message=str(payload.get("message", "")),
        metadata=metadata_dict,
        source=str(payload.get("source", "")),
        file=str(payload.get("file", "")),
        function=str(payload.get("function", "")),
        line=int(payload.get("line", 0)),
    )


def load_entries(path: Path) -> tuple[list[Entry], list[str]]:
    entries: list[Entry] = []
    parse_errors: list[str] = []

    with path.open("r", encoding="utf-8") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            stripped = raw_line.strip()
            if not stripped:
                continue
            try:
                entries.append(parse_entry(line_number, stripped))
            except Exception as exc:
                parse_errors.append(f"line {line_number}: {exc}")

    return entries, parse_errors


def matches_text(value: str, needle: str | None) -> bool:
    if not needle:
        return True
    return needle.casefold() in value.casefold()


def scope_description(args: argparse.Namespace) -> str | None:
    parts: list[str] = []
    if args.after is not None:
        parts.append(f"after {args.after}")
    if args.before is not None:
        parts.append(f"before {args.before}")
    if args.last_hours is not None:
        parts.append(f"last {args.last_hours:g}h")
    if args.tail is not None:
        parts.append(f"tail {args.tail}")
    return ", ".join(parts) if parts else None


def apply_scope(entries: list[Entry], args: argparse.Namespace) -> list[Entry]:
    scoped_entries = entries

    if args.after is not None and scoped_entries:
        cutoff_ms = parse_time_arg(args.after)
        scoped_entries = [
            entry for entry in scoped_entries if entry.timestamp_ms >= cutoff_ms
        ]

    if args.before is not None and scoped_entries:
        cutoff_ms = parse_time_arg(args.before)
        scoped_entries = [
            entry for entry in scoped_entries if entry.timestamp_ms <= cutoff_ms
        ]

    if args.last_hours is not None and scoped_entries:
        latest_timestamp_ms = max(entry.timestamp_ms for entry in scoped_entries)
        cutoff_ms = latest_timestamp_ms - int(args.last_hours * 60 * 60 * 1000)
        scoped_entries = [
            entry for entry in scoped_entries if entry.timestamp_ms >= cutoff_ms
        ]

    if args.tail is not None:
        scoped_entries = scoped_entries[-args.tail :]

    return scoped_entries


def filters_applied(args: argparse.Namespace) -> bool:
    return any(
        value is not None
        for value in [
            args.min_level,
            args.around,
            args.match,
            args.subsystem,
            args.category,
            args.source,
            args.file,
            args.function,
        ]
    )


def selection_constraints(args: argparse.Namespace) -> dict[str, Any]:
    constraints: dict[str, Any] = {}
    for key in [
        "min_level",
        "around",
        "window_ms",
        "match",
        "subsystem",
        "category",
        "source",
        "file",
        "function",
        "after",
        "before",
        "last_hours",
        "tail",
        "coalesce_window_ms",
    ]:
        value = getattr(args, key)
        if value is not None:
            constraints[key] = value
    return constraints


def entry_matches(entry: Entry, args: argparse.Namespace, min_level: int | None) -> bool:
    if min_level is not None and entry.level < min_level:
        return False

    if args.around is not None and abs(entry.timestamp_ms - args.around) > args.window_ms:
        return False

    if not matches_text(entry.subsystem, args.subsystem):
        return False
    if not matches_text(entry.category, args.category):
        return False
    if not matches_text(entry.source, args.source):
        return False
    if not matches_text(entry.file, args.file):
        return False
    if not matches_text(entry.function, args.function):
        return False

    if args.match:
        haystack = " ".join(
            [
                entry.message,
                entry.source,
                entry.subsystem,
                entry.category,
                entry.file,
                entry.function,
                json.dumps(entry.metadata or {}, sort_keys=True),
            ]
        ).casefold()
        if args.match.casefold() not in haystack:
            return False

    return True


def issue_group_key(entry: Entry) -> tuple[Any, ...]:
    return (
        entry.level,
        entry.source,
        entry.subsystem,
        entry.category,
        entry.file,
        entry.function,
        entry.line,
        entry.message,
        tuple(sorted((entry.metadata or {}).items())),
    )


def build_issue_groups(entries: list[Entry]) -> dict[tuple[Any, ...], IssueGroup]:
    groups: dict[tuple[Any, ...], IssueGroup] = {}

    for entry in entries:
        if entry.level < LEVEL_VALUES["warning"]:
            continue

        key = issue_group_key(entry)
        existing = groups.get(key)
        if existing is None:
            groups[key] = IssueGroup(
                entry=entry,
                count=1,
                first_timestamp_ms=entry.timestamp_ms,
                last_timestamp_ms=entry.timestamp_ms,
            )
            continue

        existing.add(entry)

    return groups


def rank_issue_groups(groups: dict[tuple[Any, ...], IssueGroup]) -> list[IssueGroup]:
    return sorted(
        groups.values(),
        key=lambda group: (group.count, group.last_timestamp_ms),
        reverse=True,
    )


def burst_key(entry: Entry) -> tuple[Any, ...]:
    return (
        entry.level,
        entry.source,
        entry.subsystem,
        entry.category,
        entry.message,
        tuple(sorted((entry.metadata or {}).items())),
        entry.file,
        entry.function,
        entry.line,
    )


def coalesce_entries(entries: list[Entry], window_ms: int) -> list[EntryBurst]:
    if not entries:
        return []

    if window_ms <= 0:
        return [EntryBurst(first_entry=entry, last_entry=entry) for entry in entries]

    bursts: list[EntryBurst] = []
    current = EntryBurst(first_entry=entries[0], last_entry=entries[0])
    current_key = burst_key(entries[0])

    for entry in entries[1:]:
        same_burst = (
            burst_key(entry) == current_key
            and entry.timestamp_ms - current.last_entry.timestamp_ms <= window_ms
        )
        if same_burst:
            current.last_entry = entry
            current.count += 1
            continue

        bursts.append(current)
        current = EntryBurst(first_entry=entry, last_entry=entry)
        current_key = burst_key(entry)

    bursts.append(current)
    return bursts


def cadence_summary(group: IssueGroup) -> dict[str, Any] | None:
    if group.gap_count == 0:
        return None

    average_gap_ms = int(group.gap_sum_ms / group.gap_count)
    return {
        "intervals": group.gap_count,
        "average_gap_ms": average_gap_ms,
        "average_gap_human": format_duration(average_gap_ms),
        "min_gap_ms": group.min_gap_ms,
        "min_gap_human": format_duration(group.min_gap_ms or 0),
        "max_gap_ms": group.max_gap_ms,
        "max_gap_human": format_duration(group.max_gap_ms or 0),
    }


def decode_network_annotations(text: str) -> list[dict[str, Any]]:
    annotations: list[dict[str, Any]] = []
    seen_codes: set[int] = set()

    for match in URL_ERROR_PATTERN.finditer(text):
        code = int(match.group("code"))
        if code in seen_codes:
            continue
        seen_codes.add(code)

        name, description = URL_ERROR_CODES.get(
            code,
            ("unknown", "Unknown URL loading error code."),
        )
        annotations.append(
            {
                "domain": "NSURLErrorDomain",
                "code": code,
                "name": name,
                "description": description,
            }
        )

    return annotations


def describe_origin(entry: Entry) -> str:
    if entry.file or entry.function or entry.line:
        if entry.function:
            return f"{entry.file}:{entry.line} in {entry.function}"
        return f"{entry.file}:{entry.line}"
    return "<unknown>"


def serialize_entry(entry: Entry) -> dict[str, Any]:
    return {
        "line_number": entry.line_number,
        "timestamp_ms": entry.timestamp_ms,
        "timestamp_pt": format_timestamp(entry.timestamp_ms),
        "level": entry.level,
        "level_name": entry.level_name,
        "source": entry.source,
        "subsystem": entry.subsystem,
        "category": entry.category,
        "file": entry.file,
        "function": entry.function,
        "source_line": entry.line,
        "message": entry.message,
        "metadata": entry.metadata,
        "network_annotations": decode_network_annotations(entry.message),
    }


def serialize_burst(burst: EntryBurst) -> dict[str, Any]:
    first_entry = burst.first_entry
    return {
        "count": burst.count,
        "first_entry": serialize_entry(burst.first_entry),
        "last_entry": serialize_entry(burst.last_entry),
        "origin": describe_origin(first_entry),
    }


def serialize_issue_group(group: IssueGroup) -> dict[str, Any]:
    entry = group.entry
    return {
        "count": group.count,
        "level_name": entry.level_name,
        "source": entry.source,
        "subsystem": entry.subsystem,
        "category": entry.category,
        "origin": describe_origin(entry),
        "source_line_number": entry.line_number,
        "message": entry.message,
        "metadata": entry.metadata,
        "first_timestamp_ms": group.first_timestamp_ms,
        "first_timestamp_pt": format_timestamp(group.first_timestamp_ms),
        "last_timestamp_ms": group.last_timestamp_ms,
        "last_timestamp_pt": format_timestamp(group.last_timestamp_ms),
        "cadence": cadence_summary(group),
        "network_annotations": decode_network_annotations(entry.message),
    }


def build_report(path: Path, args: argparse.Namespace) -> Report:
    file_entries, parse_errors = load_entries(path)
    active_entries = apply_scope(file_entries, args)
    min_level = LEVEL_VALUES[args.min_level] if args.min_level else None
    filtered = filters_applied(args)
    selected_entries = [
        entry for entry in active_entries if entry_matches(entry, args, min_level)
    ] if filtered else active_entries
    selected_bursts = coalesce_entries(selected_entries, args.coalesce_window_ms)
    group_map = build_issue_groups(active_entries)

    return Report(
        path=path,
        parse_errors=parse_errors,
        file_entries=file_entries,
        active_entries=active_entries,
        selection_entries=selected_entries,
        selection_bursts=selected_bursts,
        issue_groups=rank_issue_groups(group_map),
        issue_group_map=group_map,
        scope_applied=scope_description(args) is not None,
        filters_applied=filtered,
        scope_description=scope_description(args),
    )


def report_to_dict(report: Report, args: argparse.Namespace) -> dict[str, Any]:
    active_levels = Counter(entry.level_name for entry in report.active_entries)
    active_sources = Counter(entry.source for entry in report.active_entries)
    active_subsystems = Counter(entry.subsystem for entry in report.active_entries)
    selected_levels = Counter(entry.level_name for entry in report.selection_entries)

    return {
        "file": str(report.path),
        "parsed_entries": len(report.file_entries),
        "parse_error_count": len(report.parse_errors),
        "parse_errors": report.parse_errors,
        "file_range": range_summary(report.file_entries),
        "scope": {
            "applied": report.scope_applied,
            "description": report.scope_description,
        },
        "active_entries": len(report.active_entries),
        "active_range": range_summary(report.active_entries),
        "active_levels": counter_to_dict(active_levels),
        "active_sources": counter_to_dict(active_sources),
        "active_subsystems": counter_to_dict(active_subsystems, limit=8),
        "top_issues": [serialize_issue_group(group) for group in report.issue_groups[: args.top]],
        "selection": {
            "constraints": selection_constraints(args),
            "entry_count": len(report.selection_entries),
            "burst_count": len(report.selection_bursts),
            "range": range_summary(report.selection_entries),
            "levels": counter_to_dict(selected_levels),
            "bursts": [
                serialize_burst(burst) for burst in report.selection_bursts[: args.limit]
            ],
        },
    }


def print_time_range(label: str, entries: list[Entry]) -> None:
    summary = range_summary(entries)
    if summary is None:
        print(f"{label}: none")
        return

    print(
        f"{label}: {summary['start_pt']} -> {summary['end_pt']} "
        f"({summary['duration_human']})"
    )


def print_issue_groups(issue_groups: list[IssueGroup], top: int) -> None:
    print("Top warnings/errors:")
    if not issue_groups:
        print("  none")
        return

    for group in issue_groups[:top]:
        entry = group.entry
        print(
            f"  {group.count}x {entry.level_name} {entry.source} "
            f"{entry.subsystem}/{entry.category}"
        )
        print(f"    origin: {describe_origin(entry)}")
        print(
            "    first/last: "
            f"{format_timestamp(group.first_timestamp_ms)} -> "
            f"{format_timestamp(group.last_timestamp_ms)}"
        )

        cadence = cadence_summary(group)
        if cadence is not None:
            print(
                "    cadence: "
                f"avg {cadence['average_gap_human']} gap "
                f"(min {cadence['min_gap_human']}, max {cadence['max_gap_human']})"
            )

        if entry.metadata:
            metadata_text = ", ".join(
                f"{key}={value}" for key, value in sorted(entry.metadata.items())
            )
            print(f"    metadata: {metadata_text}")

        for annotation in decode_network_annotations(entry.message):
            print(
                "    network: "
                f"{annotation['domain']} {annotation['code']} "
                f"({annotation['name']}) - {annotation['description']}"
            )

        print("    message:")
        print(indent_block(entry.message))


def print_bursts(bursts: list[EntryBurst], limit: int) -> None:
    print(f"Entries (showing up to {limit}):")
    if not bursts:
        print("  none")
        return

    for burst in bursts[:limit]:
        entry = burst.first_entry
        if burst.count == 1:
            heading = (
                f"  [{entry.line_number}] {format_timestamp(entry.timestamp_ms)} "
                f"{entry.level_name} {entry.source} {entry.subsystem}/{entry.category}"
            )
        else:
            heading = (
                f"  [{burst.first_entry.line_number}..{burst.last_entry.line_number}] "
                f"{format_timestamp(burst.first_entry.timestamp_ms)} -> "
                f"{format_timestamp(burst.last_entry.timestamp_ms)} "
                f"{entry.level_name} {entry.source} {entry.subsystem}/{entry.category} "
                f"({burst.count}x burst)"
            )
        print(heading)
        print(f"    origin: {describe_origin(entry)}")
        print("    message:")
        print(indent_block(entry.message))
        if entry.metadata:
            metadata_text = ", ".join(
                f"{key}={value}" for key, value in sorted(entry.metadata.items())
            )
            print(f"    metadata: {metadata_text}")
        for annotation in decode_network_annotations(entry.message):
            print(
                "    network: "
                f"{annotation['domain']} {annotation['code']} "
                f"({annotation['name']}) - {annotation['description']}"
            )


def compare_counter_maps(left: Counter[str], right: Counter[str], limit: int = 8) -> list[dict[str, Any]]:
    keys = set(left) | set(right)
    deltas = [
        {
            "key": key,
            "left": left.get(key, 0),
            "right": right.get(key, 0),
            "delta": right.get(key, 0) - left.get(key, 0),
        }
        for key in keys
        if left.get(key, 0) != right.get(key, 0)
    ]
    deltas.sort(key=lambda item: (abs(item["delta"]), item["right"], item["left"]), reverse=True)
    return deltas[:limit]


def compare_issue_groups(
    left: dict[tuple[Any, ...], IssueGroup],
    right: dict[tuple[Any, ...], IssueGroup],
    limit: int,
) -> list[dict[str, Any]]:
    keys = set(left) | set(right)
    deltas: list[dict[str, Any]] = []

    for key in keys:
        left_group = left.get(key)
        right_group = right.get(key)
        left_count = left_group.count if left_group else 0
        right_count = right_group.count if right_group else 0
        if left_count == right_count:
            continue

        sample = right_group or left_group
        assert sample is not None
        deltas.append(
            {
                "level_name": sample.entry.level_name,
                "source": sample.entry.source,
                "subsystem": sample.entry.subsystem,
                "category": sample.entry.category,
                "origin": describe_origin(sample.entry),
                "message": sample.entry.message,
                "left": left_count,
                "right": right_count,
                "delta": right_count - left_count,
            }
        )

    deltas.sort(key=lambda item: (abs(item["delta"]), item["right"], item["left"]), reverse=True)
    return deltas[:limit]


def compare_reports(left: Report, right: Report, args: argparse.Namespace) -> dict[str, Any]:
    left_levels = Counter(entry.level_name for entry in left.active_entries)
    right_levels = Counter(entry.level_name for entry in right.active_entries)
    left_subsystems = Counter(entry.subsystem for entry in left.active_entries)
    right_subsystems = Counter(entry.subsystem for entry in right.active_entries)

    return {
        "left_file": str(left.path),
        "right_file": str(right.path),
        "left_active_entries": len(left.active_entries),
        "right_active_entries": len(right.active_entries),
        "active_entry_delta": len(right.active_entries) - len(left.active_entries),
        "left_selection_entries": len(left.selection_entries),
        "right_selection_entries": len(right.selection_entries),
        "selection_entry_delta": len(right.selection_entries) - len(left.selection_entries),
        "level_deltas": compare_counter_maps(left_levels, right_levels, limit=8),
        "subsystem_deltas": compare_counter_maps(left_subsystems, right_subsystems, limit=8),
        "issue_deltas": compare_issue_groups(left.issue_group_map, right.issue_group_map, args.top),
    }


def print_report(report: Report, args: argparse.Namespace) -> None:
    print(f"File: {report.path}")
    print(f"Parsed entries: {len(report.file_entries)}")
    if report.parse_errors:
        print(f"Parse errors: {len(report.parse_errors)}")
        for error in report.parse_errors[:5]:
            print(f"  {error}")

    print_time_range("File range", report.file_entries)
    if report.scope_applied:
        print(f"Active scope: {report.scope_description}")
    print(f"Active entries: {len(report.active_entries)}")
    print_time_range("Active range", report.active_entries)
    print(
        "Active levels: "
        f"{format_counter(Counter(entry.level_name for entry in report.active_entries))}"
    )
    print(
        "Sources: "
        f"{format_counter(Counter(entry.source for entry in report.active_entries))}"
    )
    print(
        "Subsystems: "
        f"{format_counter(Counter(entry.subsystem for entry in report.active_entries), limit=8)}"
    )

    print_issue_groups(report.issue_groups, args.top)

    should_show_selection = report.scope_applied or report.filters_applied
    if should_show_selection:
        print()
        print(f"Matching entries: {len(report.selection_entries)}")
        if args.coalesce_window_ms > 0:
            print(
                f"Matching bursts: {len(report.selection_bursts)} "
                f"(coalesce window: {args.coalesce_window_ms}ms)"
            )
        print_time_range("Matching range", report.selection_entries)
        print(
            "Matching levels: "
            f"{format_counter(Counter(entry.level_name for entry in report.selection_entries))}"
        )
        print_bursts(report.selection_bursts, args.limit)


def print_comparison(left: Report, right: Report, args: argparse.Namespace) -> None:
    comparison = compare_reports(left, right, args)
    print("Compare mode:")
    print(f"  left: {comparison['left_file']}")
    print(f"  right: {comparison['right_file']}")
    print(
        f"  active entries: {comparison['left_active_entries']} -> "
        f"{comparison['right_active_entries']} "
        f"(delta {comparison['active_entry_delta']:+d})"
    )
    print(
        f"  selection entries: {comparison['left_selection_entries']} -> "
        f"{comparison['right_selection_entries']} "
        f"(delta {comparison['selection_entry_delta']:+d})"
    )

    print("  level deltas:")
    if comparison["level_deltas"]:
        for delta in comparison["level_deltas"]:
            print(
                f"    {delta['key']}: {delta['left']} -> {delta['right']} "
                f"(delta {delta['delta']:+d})"
            )
    else:
        print("    none")

    print("  subsystem deltas:")
    if comparison["subsystem_deltas"]:
        for delta in comparison["subsystem_deltas"]:
            print(
                f"    {delta['key']}: {delta['left']} -> {delta['right']} "
                f"(delta {delta['delta']:+d})"
            )
    else:
        print("    none")

    print("  recurring issue deltas:")
    if comparison["issue_deltas"]:
        for delta in comparison["issue_deltas"]:
            print(
                f"    {delta['level_name']} {delta['subsystem']}/{delta['category']} "
                f"{delta['left']} -> {delta['right']} (delta {delta['delta']:+d})"
            )
            print(f"      origin: {delta['origin']}")
            print("      message:")
            print(indent_block(delta["message"], prefix="        "))
    else:
        print("    none")


def detect_sessions(entries: list[Entry], gap_threshold_ms: int = 5000) -> list[dict[str, Any]]:
    """Detect app sessions by looking for launch-related log entries."""
    session_starts: list[tuple[int, int]] = []  # (timestamp_ms, index)

    for i, e in enumerate(entries):
        is_launch = (
            (e.subsystem == "PodHaven" and e.category == "AppLauncher")
            or (e.subsystem == "Database" and "creating" in e.message and "AppDB" in e.message)
            or ("configureLogging" in e.message)
        )
        if not is_launch:
            continue
        if not session_starts or e.timestamp_ms - session_starts[-1][0] > gap_threshold_ms:
            session_starts.append((e.timestamp_ms, i))

    if not session_starts:
        return []

    sessions: list[dict[str, Any]] = []
    for j, (start_ts, start_idx) in enumerate(session_starts):
        if j + 1 < len(session_starts):
            end_idx = session_starts[j + 1][1] - 1
        else:
            end_idx = len(entries) - 1

        session_entries = entries[start_idx : end_idx + 1]
        level_counts = Counter(e.level for e in session_entries)
        end_ts = entries[end_idx].timestamp_ms
        duration_ms = end_ts - start_ts

        sessions.append({
            "number": j + 1,
            "start_ms": start_ts,
            "start_pt": format_timestamp(start_ts),
            "end_ms": end_ts,
            "end_pt": format_timestamp(end_ts),
            "duration_ms": duration_ms,
            "duration_human": format_duration(duration_ms),
            "entry_count": len(session_entries),
            "warnings": level_counts.get(4, 0),
            "errors": level_counts.get(5, 0) + level_counts.get(6, 0),
        })

    return sessions


def print_sessions(sessions: list[dict[str, Any]]) -> None:
    print(f"Found {len(sessions)} sessions:\n")
    for s in sessions:
        problems = []
        if s["errors"]:
            problems.append(f"{s['errors']} errors")
        if s["warnings"]:
            problems.append(f"{s['warnings']} warnings")
        prob_str = f"  [{', '.join(problems)}]" if problems else ""

        print(
            f"  Session {s['number']}: {s['start_pt']} "
            f"({s['duration_human']}, {s['entry_count']:,} entries){prob_str}"
        )


def main() -> int:
    args = parse_args()
    path = Path(args.path).expanduser()
    if not path.exists():
        print(f"Log file not found: {path}", file=sys.stderr)
        return 1

    if args.sessions:
        file_entries, parse_errors = load_entries(path)
        if not file_entries:
            print("No entries found.")
            return 0
        sessions = detect_sessions(file_entries)
        if not sessions:
            print("No session boundaries detected.")
            return 0
        if args.json_output:
            print(json.dumps({"sessions": sessions}, indent=2, sort_keys=False))
        else:
            print_sessions(sessions)
        return 0

    primary_report = build_report(path, args)

    comparison_report: Report | None = None
    if args.compare_other:
        comparison_path = Path(args.compare_other).expanduser()
        if not comparison_path.exists():
            print(f"Comparison log file not found: {comparison_path}", file=sys.stderr)
            return 1
        comparison_report = build_report(comparison_path, args)

    if args.json_output:
        payload: dict[str, Any] = {"primary": report_to_dict(primary_report, args)}
        if comparison_report is not None:
            payload["comparison"] = {
                "secondary": report_to_dict(comparison_report, args),
                "diff": compare_reports(primary_report, comparison_report, args),
            }
        print(json.dumps(payload, indent=2, sort_keys=False))
        return 0

    print_report(primary_report, args)
    if comparison_report is not None:
        print()
        print_comparison(primary_report, comparison_report, args)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
