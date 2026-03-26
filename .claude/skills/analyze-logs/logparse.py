#!/usr/bin/env python3
"""PodHaven NDJSON log parser for the analyze-logs skill.

Subcommands:
  summary   Time range, entry counts by level/subsystem/category
  errors    Show error and critical entries (level >= 4 by default)
  filter    Filter entries by level, subsystem, category, time range
  timeline  Show entries around a timestamp
"""

import argparse
import json
import sys
from collections import Counter
from datetime import datetime, UTC
from zoneinfo import ZoneInfo

PT = ZoneInfo("America/Los_Angeles")

DEFAULT_LOG = (
    "/Users/jubi/Library/Mobile Documents/"
    "com~apple~CloudDocs/Podhaven Assets/log.ndjson"
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

LEVEL_FROM_NAME = {v: k for k, v in LEVEL_NAMES.items()}


def parse_ts(ms):
    return datetime.fromtimestamp(ms / 1000, UTC).astimezone(PT)


def fmt_ts(ms):
    return parse_ts(ms).strftime("%Y-%m-%d %H:%M:%S %Z")


def parse_time_arg(s):
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
            dt = dt.replace(tzinfo=PT)
            return int(dt.timestamp() * 1000)
        except ValueError:
            continue
    # try as raw epoch ms
    try:
        return int(s)
    except ValueError:
        print(f"error: cannot parse time '{s}'", file=sys.stderr)
        sys.exit(1)


def parse_level_arg(s):
    """Parse a level name or number."""
    if s.isdigit():
        return int(s)
    s_lower = s.lower()
    if s_lower in LEVEL_FROM_NAME:
        return LEVEL_FROM_NAME[s_lower]
    print(f"error: unknown level '{s}'", file=sys.stderr)
    sys.exit(1)


def load_entries(path):
    entries = []
    with open(path) as f:
        for i, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError as e:
                print(f"warning: skipping line {i}: {e}", file=sys.stderr)
    return entries


def format_entry(e, verbose=False):
    """Format one log entry as a readable string."""
    ts = fmt_ts(e["timestamp"])
    level = e.get("levelName", LEVEL_NAMES.get(e.get("level", -1), "?"))
    sub = e.get("subsystem", "?")
    cat = e.get("category", "?")
    msg = e.get("message", "").replace("\\n", "\n")

    header = f"[{ts}] {level.upper():>8}  {sub}/{cat}"
    lines = [header, f"  {msg}"]

    if verbose:
        meta = e.get("metadata")
        if meta:
            lines.append(f"  metadata: {json.dumps(meta)}")
        func = e.get("function", "")
        file = e.get("file", "")
        ln = e.get("line", "")
        if func or file:
            lines.append(f"  at {file}:{ln} {func}")

    return "\n".join(lines)


def apply_filters(entries, args):
    """Apply common filters (level, subsystem, category, after, before, search)."""
    result = entries

    if hasattr(args, "min_level") and args.min_level is not None:
        lvl = parse_level_arg(args.min_level)
        result = [e for e in result if e.get("level", 0) >= lvl]

    if hasattr(args, "level") and args.level is not None:
        lvl = parse_level_arg(args.level)
        result = [e for e in result if e.get("level", 0) == lvl]

    if hasattr(args, "subsystem") and args.subsystem:
        s = args.subsystem.lower()
        result = [e for e in result if e.get("subsystem", "").lower() == s]

    if hasattr(args, "category") and args.category:
        c = args.category.lower()
        result = [e for e in result if e.get("category", "").lower() == c]

    if hasattr(args, "after") and args.after:
        t = parse_time_arg(args.after)
        result = [e for e in result if e.get("timestamp", 0) >= t]

    if hasattr(args, "before") and args.before:
        t = parse_time_arg(args.before)
        result = [e for e in result if e.get("timestamp", 0) <= t]

    if hasattr(args, "source") and args.source:
        s = args.source.lower()
        result = [e for e in result if e.get("source", "").lower() == s]

    if hasattr(args, "search") and args.search:
        q = args.search.lower()
        result = [e for e in result if q in e.get("message", "").lower()]

    return result


def cmd_summary(args):
    entries = load_entries(args.file)
    if not entries:
        print("No entries found.")
        return

    total = len(entries)
    timestamps = [e["timestamp"] for e in entries if "timestamp" in e]
    first_ts, last_ts = min(timestamps), max(timestamps)
    span_sec = (last_ts - first_ts) / 1000

    print(f"Log file: {args.file}")
    print(f"Entries:  {total:,}")
    print(f"From:     {fmt_ts(first_ts)}")
    print(f"To:       {fmt_ts(last_ts)}")
    if span_sec < 3600:
        print(f"Span:     {span_sec / 60:.1f} minutes")
    elif span_sec < 86400:
        print(f"Span:     {span_sec / 3600:.1f} hours")
    else:
        print(f"Span:     {span_sec / 86400:.1f} days")

    # counts by level
    level_counts = Counter(
        e.get("levelName", LEVEL_NAMES.get(e.get("level"), "?"))
        for e in entries
    )
    print("\n--- By Level ---")
    for lvl_num in sorted(LEVEL_NAMES.keys()):
        name = LEVEL_NAMES[lvl_num]
        count = level_counts.get(name, 0)
        if count > 0:
            pct = count / total * 100
            print(f"  {name:>8}: {count:>6,}  ({pct:.1f}%)")

    # counts by subsystem
    sub_counts = Counter(e.get("subsystem", "?") for e in entries)
    print("\n--- By Subsystem ---")
    for sub, count in sub_counts.most_common():
        print(f"  {sub:<30} {count:>6,}")

    # counts by subsystem/category
    cat_counts = Counter(
        f"{e.get('subsystem', '?')}/{e.get('category', '?')}" for e in entries
    )
    print("\n--- By Subsystem/Category ---")
    for cat, count in cat_counts.most_common(20):
        print(f"  {cat:<40} {count:>6,}")
    if len(cat_counts) > 20:
        print(f"  ... and {len(cat_counts) - 20} more")


def group_key(e):
    """Key for grouping duplicate entries: message + source location."""
    return (
        e.get("message", ""),
        e.get("subsystem", ""),
        e.get("category", ""),
        e.get("file", ""),
        e.get("line", 0),
    )


def cmd_errors(args):
    entries = load_entries(args.file)
    min_lvl = parse_level_arg(args.min_level)
    filtered = [e for e in entries if e.get("level", 0) >= min_lvl]
    # apply additional filters (after, before, subsystem, etc.)
    args_min = args.min_level
    args.min_level = None
    filtered = apply_filters(filtered, args)
    args.min_level = args_min

    if not filtered:
        lvl_name = LEVEL_NAMES.get(min_lvl, str(min_lvl))
        print(f"No entries at level >= {lvl_name} ({min_lvl}).")
        return

    if args.group:
        groups = {}
        for e in filtered:
            key = group_key(e)
            if key not in groups:
                groups[key] = {"entry": e, "count": 0, "first": e["timestamp"], "last": e["timestamp"]}
            groups[key]["count"] += 1
            groups[key]["first"] = min(groups[key]["first"], e["timestamp"])
            groups[key]["last"] = max(groups[key]["last"], e["timestamp"])

        sorted_groups = sorted(groups.values(), key=lambda g: g["count"], reverse=True)
        print(
            f"Found {len(filtered)} entries at level >= "
            f"{LEVEL_NAMES.get(min_lvl, str(min_lvl))}, "
            f"{len(sorted_groups)} unique:\n"
        )
        for g in sorted_groups:
            e = g["entry"]
            print(format_entry(e, verbose=True))
            if g["count"] > 1:
                print(f"  ^^^ repeated {g['count']}x from {fmt_ts(g['first'])} to {fmt_ts(g['last'])}")
            print()
    else:
        print(f"Found {len(filtered)} entries at level >= {LEVEL_NAMES.get(min_lvl, str(min_lvl))}:\n")
        for e in filtered:
            print(format_entry(e, verbose=True))
            print()


def cmd_filter(args):
    entries = load_entries(args.file)
    filtered = apply_filters(entries, args)

    if not filtered:
        print("No entries match the filters.")
        return

    limit = args.limit or len(filtered)
    showing = filtered[-limit:] if args.tail else filtered[:limit]

    print(f"Matched {len(filtered)} entries (showing {len(showing)}):\n")
    for e in showing:
        print(format_entry(e, verbose=args.verbose))
        print()


def cmd_timeline(args):
    entries = load_entries(args.file)
    center = parse_time_arg(args.around)
    window_ms = args.window * 1000

    filtered = [
        e
        for e in entries
        if abs(e.get("timestamp", 0) - center) <= window_ms
    ]

    if args.subsystem:
        s = args.subsystem.lower()
        filtered = [e for e in filtered if e.get("subsystem", "").lower() == s]

    if args.min_level:
        lvl = parse_level_arg(args.min_level)
        filtered = [e for e in filtered if e.get("level", 0) >= lvl]

    if not filtered:
        print(f"No entries within {args.window}s of {fmt_ts(center)}.")
        return

    filtered.sort(key=lambda e: e.get("timestamp", 0))

    limit = args.limit or len(filtered)
    # show entries centered around the middle of the window
    if limit < len(filtered):
        mid = len(filtered) // 2
        start = max(0, mid - limit // 2)
        showing = filtered[start : start + limit]
    else:
        showing = filtered

    print(
        f"Timeline: {len(filtered)} entries within {args.window}s "
        f"of {fmt_ts(center)} (showing {len(showing)}):\n"
    )
    for e in showing:
        print(format_entry(e, verbose=True))
        print()


def cmd_sessions(args):
    entries = load_entries(args.file)
    if not entries:
        print("No entries found.")
        return

    # detect sessions by looking for AppLauncher entries
    sessions = []
    for i, e in enumerate(entries):
        sub = e.get("subsystem", "")
        cat = e.get("category", "")
        msg = e.get("message", "")
        if (
            (sub == "PodHaven" and cat == "AppLauncher")
            or (sub == "Database" and "creating" in msg and "AppDB" in msg)
            or ("configureLogging" in msg)
        ):
            # check if this is actually a new session start (not just another
            # AppLauncher log in the same session)
            if not sessions or e["timestamp"] - sessions[-1]["start"] > 5000:
                sessions.append({"start": e["timestamp"], "start_idx": i})

    if not sessions:
        print("No session boundaries detected.")
        return

    # compute end times and entry counts
    for j, sess in enumerate(sessions):
        if j + 1 < len(sessions):
            end_idx = sessions[j + 1]["start_idx"] - 1
        else:
            end_idx = len(entries) - 1
        sess["end"] = entries[end_idx]["timestamp"]
        sess["count"] = end_idx - sess["start_idx"] + 1

        # count levels within this session
        session_entries = entries[sess["start_idx"] : end_idx + 1]
        level_counts = Counter(e.get("level", 0) for e in session_entries)
        sess["warnings"] = level_counts.get(4, 0)
        sess["errors"] = level_counts.get(5, 0) + level_counts.get(6, 0)

    print(f"Found {len(sessions)} sessions:\n")
    for j, sess in enumerate(sessions):
        duration_s = (sess["end"] - sess["start"]) / 1000
        if duration_s < 60:
            dur = f"{duration_s:.0f}s"
        elif duration_s < 3600:
            dur = f"{duration_s / 60:.1f}m"
        else:
            dur = f"{duration_s / 3600:.1f}h"

        problems = []
        if sess["errors"]:
            problems.append(f"{sess['errors']} errors")
        if sess["warnings"]:
            problems.append(f"{sess['warnings']} warnings")
        prob_str = f"  [{', '.join(problems)}]" if problems else ""

        print(
            f"  Session {j + 1}: {fmt_ts(sess['start'])} "
            f"({dur}, {sess['count']:,} entries){prob_str}"
        )


def main():
    parser = argparse.ArgumentParser(
        description="PodHaven NDJSON log parser",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "-f", "--file", default=DEFAULT_LOG, help="Path to log file"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # summary
    sub.add_parser("summary", help="Overview: time range, counts by level/subsystem")

    # errors
    p_err = sub.add_parser("errors", help="Show entries at or above a level")
    p_err.add_argument(
        "--min-level",
        default="warning",
        help="Minimum level to show (name or number, default: warning)",
    )
    p_err.add_argument("--subsystem", help="Filter by subsystem")
    p_err.add_argument("--category", help="Filter by category")
    p_err.add_argument("--after", help="Only entries after this time")
    p_err.add_argument("--before", help="Only entries before this time")
    p_err.add_argument("--source", help="Filter by source (PodHaven or PodHavenWidget)")
    p_err.add_argument("--search", help="Search message text (case-insensitive)")
    p_err.add_argument(
        "--group",
        action="store_true",
        default=True,
        help="Group duplicate messages and show counts (default: true)",
    )
    p_err.add_argument(
        "--no-group",
        action="store_false",
        dest="group",
        help="Show every entry individually without grouping",
    )

    # filter
    p_filt = sub.add_parser("filter", help="Filter entries by multiple criteria")
    p_filt.add_argument("--level", help="Exact level (name or number)")
    p_filt.add_argument("--min-level", help="Minimum level (name or number)")
    p_filt.add_argument("--subsystem", help="Filter by subsystem")
    p_filt.add_argument("--category", help="Filter by category")
    p_filt.add_argument("--after", help="Only entries after this time")
    p_filt.add_argument("--before", help="Only entries before this time")
    p_filt.add_argument("--source", help="Filter by source (PodHaven or PodHavenWidget)")
    p_filt.add_argument("--search", help="Search message text (case-insensitive)")
    p_filt.add_argument(
        "--limit", type=int, default=50, help="Max entries to show (default 50, 0=all)"
    )
    p_filt.add_argument(
        "--tail", action="store_true", help="Show last N instead of first N"
    )
    p_filt.add_argument(
        "-v", "--verbose", action="store_true", help="Include file/function/metadata"
    )

    # timeline
    p_tl = sub.add_parser("timeline", help="Show entries around a timestamp")
    p_tl.add_argument("around", help="Center timestamp (epoch ms or datetime string)")
    p_tl.add_argument(
        "--window",
        type=int,
        default=30,
        help="Window in seconds on each side (default 30)",
    )
    p_tl.add_argument("--subsystem", help="Filter to specific subsystem")
    p_tl.add_argument("--min-level", help="Minimum level (name or number)")
    p_tl.add_argument(
        "--limit",
        type=int,
        default=50,
        help="Max entries to show, centered around the target time (default 50, 0=all)",
    )

    # sessions
    sub.add_parser(
        "sessions", help="Detect and list app sessions (launch boundaries)"
    )

    args = parser.parse_args()

    if args.command == "summary":
        cmd_summary(args)
    elif args.command == "errors":
        cmd_errors(args)
    elif args.command == "filter":
        cmd_filter(args)
    elif args.command == "timeline":
        cmd_timeline(args)
    elif args.command == "sessions":
        cmd_sessions(args)


if __name__ == "__main__":
    main()
