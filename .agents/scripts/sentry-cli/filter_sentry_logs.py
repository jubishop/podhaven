#!/usr/bin/env python3
# Filter Sentry ourlogs detail JSON to a time window around an event.
#
# Usage:
#   filter_sentry_logs.py --around-ms 1780281854316 --window-ms 600000
#   filter_sentry_logs.py --input /tmp/sentry_logs_detail.json --around-ms ... --oneline
#   filter_sentry_logs.py --around-ms ... --in-place   # rewrite input file
#
# Reads ISO timestamps from each row. Writes filtered rows to --output (default:
# /tmp/sentry_logs_detail_filtered.json) unless --in-place is set.

from __future__ import annotations

import argparse
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


def parse_timestamp_ms(row: dict) -> int | None:
    precise = row.get("timestamp_precise")
    if precise is not None:
        try:
            # Sentry ourlogs returns nanoseconds; convert to epoch milliseconds.
            return int(float(precise) // 1_000_000)
        except (TypeError, ValueError):
            pass

    raw = row.get("timestamp")
    if not raw:
        return None
    try:
        normalized = raw.replace("Z", "+00:00")
        dt = datetime.fromisoformat(normalized)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return int(dt.timestamp() * 1000)
    except ValueError:
        return None


def filter_rows(rows: list[dict], around_ms: int, window_ms: int) -> list[dict]:
    half = window_ms // 2
    start = around_ms - half
    end = around_ms + half
    filtered: list[dict] = []
    for row in rows:
        ts_ms = parse_timestamp_ms(row)
        if ts_ms is None:
            continue
        if start <= ts_ms <= end:
            filtered.append(row)
    filtered.sort(key=lambda row: parse_timestamp_ms(row) or 0)
    return filtered


def format_oneline(row: dict) -> str:
    ts_ms = parse_timestamp_ms(row)
    ts_label = datetime.fromtimestamp((ts_ms or 0) / 1000, tz=timezone.utc).isoformat()
    severity = row.get("severity", "?")
    message = (row.get("message") or "").replace("\n", " ")[:160]
    trace = row.get("trace") or "-"
    user_id = row.get("user.id") or row.get("user_id") or "-"
    return f"{ts_label}\t{severity}\ttrace={trace}\tuser.id={user_id}\t{message}"


def main() -> None:
    parser = argparse.ArgumentParser(description="Filter Sentry ourlogs detail JSON by time window.")
    parser.add_argument(
        "--input",
        default="/tmp/sentry_logs_detail.json",
        help="Detail JSON from fetch_sentry_logs.sh",
    )
    parser.add_argument(
        "--output",
        default="/tmp/sentry_logs_detail_filtered.json",
        help="Filtered detail JSON output path",
    )
    parser.add_argument("--around-ms", type=int, required=True, help="Event time in epoch milliseconds")
    parser.add_argument(
        "--window-ms",
        type=int,
        default=600_000,
        help="Window size in ms centered on --around-ms (default: 600000 = 10 minutes)",
    )
    parser.add_argument(
        "--in-place",
        action="store_true",
        help="Rewrite --input with filtered rows instead of writing --output",
    )
    parser.add_argument(
        "--oneline",
        action="store_true",
        help="Print one line per filtered entry to stdout",
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    payload = json.loads(input_path.read_text())
    rows = payload.get("data", [])
    filtered = filter_rows(rows, args.around_ms, args.window_ms)

    payload["data"] = filtered
    output_path = input_path if args.in_place else Path(args.output)
    output_path.write_text(json.dumps(payload, indent=2))

    print(f"Filtered {len(filtered)} of {len(rows)} entries")
    print(f"Window: ±{args.window_ms // 2}ms around {args.around_ms}")
    print(f"Wrote: {output_path}")

    if filtered:
        environments = Counter(row.get("environment") for row in filtered)
        releases = Counter(row.get("release") for row in filtered)
        print(f"Environments: {dict(environments)}")
        print(f"Releases: {dict(releases.most_common(3))}")

    if args.oneline:
        print()
        for row in filtered:
            print(format_oneline(row))


if __name__ == "__main__":
    main()
