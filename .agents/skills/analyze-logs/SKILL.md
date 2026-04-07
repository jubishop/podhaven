---
name: analyze-logs
description: Analyze PodHaven NDJSON log files and reconstruct failure timelines. Use when inspecting log.ndjson or widget-log.ndjson, diagnosing warnings or errors, correlating a Sentry timestamp to local logs, or explaining what happened around a specific time, subsystem, category, source file, or message.
---

# Analyze Logs

Inspect PodHaven NDJSON logs without reading the entire file into context. Use the bundled summary script for structured analysis, then targeted `rg` searches when you need line-level confirmation.

## Quick Start

1. Determine the log path.
   - Use the user-provided path first.
   - Default: `/Users/jubi/Library/Mobile Documents/com~apple~CloudDocs/Podhaven Assets/log.ndjson`.
   - Widget logs: look for `widget-log.ndjson` instead.
2. Run the script with no filters for the initial overview.
3. Add structural filters (`--subsystem`, `--category`, `--source`, `--file`, `--function`) before falling back to broad `--match`.
4. Use `--last-hours`, `--tail`, `--after`/`--before` to narrow time ranges.
5. Use `--sessions` to find app launch boundaries and problem counts.
6. Use `--json` when the next step needs machine-readable output.
7. Use `--compare-other` when the user gives both app and widget logs or asks for a before/after comparison.
8. Use `rg` on the raw file to zoom in on specific timestamps, levels, subsystems, or messages.
9. Read `references/podhaven-log-format.md` only if you need field or truncation details.

## Commands

```bash
# Overview: time range, level counts, subsystem breakdown, top recurring issues
python3 scripts/log_summary.py
python3 scripts/log_summary.py "$LOG_PATH"

# Session detection: find app launches with per-session problem counts
python3 scripts/log_summary.py --sessions
python3 scripts/log_summary.py --sessions --json

# Filter by level
python3 scripts/log_summary.py --min-level error
python3 scripts/log_summary.py --min-level warning --coalesce-window-ms 0

# Filter by time range
python3 scripts/log_summary.py --last-hours 6 --min-level warning
python3 scripts/log_summary.py --after "2026-04-03" --before "2026-04-04"
python3 scripts/log_summary.py --after "2026-04-03 10:00" --before "2026-04-03 12:00"

# Filter by structure
python3 scripts/log_summary.py --subsystem Feed --category refreshManager --function refreshSeries
python3 scripts/log_summary.py --source PodHavenWidget
python3 scripts/log_summary.py --file PlayManager.swift

# Timeline around a specific event
python3 scripts/log_summary.py --around 1768679500000 --window-ms 30000

# Text search across all fields
python3 scripts/log_summary.py --match "cache load failed" --min-level warning

# Show last N entries
python3 scripts/log_summary.py --tail 200 --json

# Compare two log files (e.g. app vs widget, or before vs after)
python3 scripts/log_summary.py "$LOG_PATH" --compare-other "$OTHER_LOG_PATH"

# Raw rg searches when you need line-level precision
rg -n '"level":(4|5|6)' "$LOG_PATH"
rg -n '"timestamp":17686795' "$LOG_PATH"
rg -n '"subsystem":"Play"|"category":"refreshScheduler"' "$LOG_PATH"
```

## Flags Reference

### Scope (narrows the active view before analysis)
| Flag | Description |
|------|-------------|
| `--after TIME` | Only entries after this time (datetime string or epoch ms) |
| `--before TIME` | Only entries before this time |
| `--last-hours N` | Restrict to entries within N hours of the latest entry |
| `--tail N` | Keep only the last N entries after other scope filters |

Time arguments accept: `YYYY-MM-DD HH:MM:SS`, `YYYY-MM-DD HH:MM`, `YYYY-MM-DD`, `MM/DD HH:MM`, or raw epoch milliseconds.

### Selection filters (choose which entries to display)
| Flag | Description |
|------|-------------|
| `--min-level LEVEL` | Minimum level: trace, debug, info, notice, warning, error, critical |
| `--around TIMESTAMP_MS` | Select entries within `--window-ms` of this timestamp |
| `--window-ms N` | Window size for `--around` (default: 30000) |
| `--subsystem NAME` | Case-insensitive subsystem filter |
| `--category NAME` | Case-insensitive category filter |
| `--source NAME` | Case-insensitive source filter (e.g. PodHaven, PodHavenWidget) |
| `--file NAME` | Case-insensitive source-file filter |
| `--function NAME` | Case-insensitive function-name filter |
| `--match TEXT` | Case-insensitive search across message, metadata, and all structural fields |

### Display controls
| Flag | Description |
|------|-------------|
| `--top N` | Number of recurring warning/error families to show (default: 8) |
| `--limit N` | Number of selected entries or bursts to print (default: 20) |
| `--coalesce-window-ms N` | Collapse consecutive duplicate entries into bursts (default: 1000, 0=disable) |
| `--json` | Emit machine-readable JSON instead of text |
| `--sessions` | Detect and list app sessions (launch boundaries) with problem counts |
| `--compare-other PATH` | Compare the primary log to another log using the same filters |

## Workflow

### 1. Orient

- Run the script with no filters to get the parsed entry count, time range, level distribution, top sources/subsystems, and recurring warning/error families.
- Use `--sessions` to identify app launch boundaries and which sessions have problems.
- The recurring issue section groups by logger location, message, and metadata, and includes cadence (avg/min/max gap between occurrences) plus NSURLErrorDomain decoding.
- Present all user-facing timestamps in Pacific Time.

### 2. Find candidate failures

- Prioritize `error` and `critical` entries.
- Include `warning` entries when they plausibly lead to a later failure or show repeated unhealthy behavior.
- Watch for repeated messages, bursts in the same time window, and the same subsystem/category appearing across multiple entries.

### 3. Reconstruct the timeline

- Use `--around` with a narrow `--window-ms` to see what happened around a specific event.
- Use `--after`/`--before` for broader time ranges.
- Correlate `source`, `subsystem`, `category`, `file`, `function`, and `metadata` to identify the code path.
- Use `rg` on the raw file for timestamp-prefix searches when you already know the exact millisecond.

### 4. Correlate external references

- If the user gives a Sentry timestamp, convert it to milliseconds and use `--around`.
- If the user gives a subsystem, category, source file, or function name, prefer the dedicated flags before using `rg`.
- If the user gives multiple log files, analyze them separately first, then use `--compare-other` for a side-by-side diff.

## Reporting

- State the time range and timezone explicitly.
- Separate direct observations from inferred root cause.
- Quote only the minimum log text needed to support the conclusion.
- Mention possible missing lead-up context when the file appears truncated from the top.

## Resources

- `scripts/log_summary.py` — primary analysis tool
- `references/podhaven-log-format.md` — entry schema, log file names, and truncation behavior
