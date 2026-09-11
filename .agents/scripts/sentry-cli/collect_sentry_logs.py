#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path


def effective_query(query: str) -> str:
    query = query.strip()
    unquoted = re.sub(r"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'", " ", query)
    if re.search(r"(?:^|[\s(])!?(?:severity|level|severity_number):", unquoted):
        return query
    return f"{query} severity:[warn,error]" if query else "severity:[warn,error]"


def fixed_period(value: str) -> str:
    duration = re.fullmatch(r"([1-9][0-9]*)([smhdw])", value.strip())
    if duration:
        seconds = {"s": 1, "m": 60, "h": 3600, "d": 86400, "w": 604800}
        end = datetime.now(timezone.utc)
        start = end - timedelta(seconds=int(duration[1]) * seconds[duration[2]])
    else:
        bounds = value.split("..")
        if len(bounds) != 2 or not all(bounds):
            raise ValueError(
                "Use a positive duration (12h, 2d, 1w) or a bounded ISO datetime range"
            )
        start, end = (
            datetime.fromisoformat(bound.replace("Z", "+00:00")) for bound in bounds
        )
        if start.tzinfo is None or end.tzinfo is None:
            raise ValueError(
                "ISO datetime range boundaries must include timezone offsets"
            )
        if start >= end:
            raise ValueError("The time window must end after it starts")
    return f"{start.isoformat()}..{end.isoformat()}"


def request(command: list[str]) -> dict:
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.stderr:
        print(result.stderr, file=sys.stderr, end="")
    if result.returncode:
        raise ValueError(f"Sentry {command[1]} failed (exit {result.returncode})")
    payload = json.loads(result.stdout)
    if not isinstance(payload, dict) or not isinstance(payload.get("data"), list):
        raise TypeError("Sentry returned an invalid data envelope")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Collect complete log counts and a detail sample"
    )
    parser.add_argument("--sentry", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--period", required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--query", default="")
    args = parser.parse_args()
    rows: dict[tuple, dict] = {}
    coverage = {
        "target": args.target,
        "requested_period": args.period,
        "query": effective_query(args.query),
        "summary": "partial",
        "detail": "unavailable",
        "summary_pages": 0,
        "detail_rows": 0,
    }
    try:
        coverage["period"] = fixed_period(args.period)
        common = [
            "--query",
            coverage["query"],
            "--period",
            coverage["period"],
            "--fresh",
            "--json",
        ]
        command = [
            args.sentry,
            "explore",
            args.target,
            "--dataset",
            "logs",
            "--field",
            "severity",
            "--field",
            "message",
            "--field",
            "count()",
            "--limit",
            "100",
            *common,
        ]
        cursor = "first"
        seen_cursors = set()
        while True:
            page = request([*command, "--cursor", cursor])
            coverage["summary_pages"] += 1
            for row in page["data"]:
                if (
                    not isinstance(row, dict)
                    or not isinstance(row.get("severity"), (str, type(None)))
                    or not isinstance(row.get("message"), (str, type(None)))
                    or "severity" not in row
                    or "message" not in row
                    or type(row.get("count()")) is not int
                    or row["count()"] < 0
                ):
                    raise ValueError("Sentry returned an invalid aggregate row")
                key = (row["severity"], row["message"])
                if key in rows:
                    raise ValueError(
                        "Aggregate pages repeated a group; counts may have changed during retrieval"
                    )
                rows[key] = row
            if type(page.get("hasMore")) is not bool:
                raise ValueError("Sentry omitted aggregate pagination metadata")
            if not page["hasMore"]:
                coverage["summary"] = "complete"
                break
            cursor = page.get("nextCursor")
            if (
                not isinstance(cursor, str)
                or not cursor
                or cursor == "first"
                or cursor in seen_cursors
            ):
                raise ValueError(
                    "Sentry returned a missing or repeated aggregate cursor"
                )
            seen_cursors.add(cursor)

        detail = request(
            [args.sentry, "log", "list", args.target, "--limit", "1000", *common]
        )
        (args.out / "detail.json").write_text(json.dumps(detail, indent=2) + "\n")
        coverage["detail_rows"] = len(detail["data"])
        total = sum(row["count()"] for row in rows.values())
        coverage["detail"] = (
            "complete"
            if detail.get("hasMore") is False and len(detail["data"]) == total
            else "sample"
        )
    except (OSError, ValueError, TypeError, OverflowError) as error:
        coverage["error"] = str(error)
        print(f"Error: {error}", file=sys.stderr)
    finally:
        counts = Counter()
        for row in rows.values():
            counts[row["severity"] or "unknown"] += row["count()"]
        coverage["counts_by_severity"] = dict(counts)
        summary = {
            "data": sorted(rows.values(), key=lambda row: -row["count()"]),
            "hasMore": coverage["summary"] != "complete",
        }
        (args.out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        (args.out / "coverage.json").write_text(json.dumps(coverage, indent=2) + "\n")

    print(f"Aggregate coverage: {coverage['summary']} ({len(rows)} groups)")
    print(f"Detail coverage: {coverage['detail']} ({coverage['detail_rows']} entries)")
    print(f"Output: {args.out}")
    return 1 if "error" in coverage else 0


if __name__ == "__main__":
    sys.exit(main())
