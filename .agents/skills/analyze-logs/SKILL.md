---
name: analyze-logs
description: Analyze PodHaven NDJSON log files and reconstruct failure timelines. Use when Codex needs to inspect `log.ndjson` or `widget-log.ndjson`, diagnose warnings or errors from exported app logs or feedback attachments, correlate a Sentry timestamp to local logs, or explain what happened around a specific time, subsystem, category, source file, or message.
---

# Analyze Logs

Use this skill to inspect PodHaven NDJSON logs without reading the entire file into context. Start with the bundled summary script, then use targeted `rg` searches against the raw file only when you need line-level confirmation.

## Quick Start

1. Determine the log path.
   - Use the user-provided path first.
   - If none is provided, try `/Users/jubi/Library/Mobile Documents/com~apple~CloudDocs/Podhaven Assets/log.ndjson`.
   - If the request is explicitly about the widget, look for `widget-log.ndjson` instead.
2. Run `python3 scripts/log_summary.py "$LOG_PATH"` for the initial pass.
3. Add structural filters like `--subsystem`, `--category`, `--source`, `--file`, or `--function` before falling back to broad text matching.
4. Use `--last-hours` or `--tail` when the user only cares about recent activity.
5. Use `--json` when the next step needs machine-readable output.
6. Use `--compare-other OTHER_LOG_PATH` when the user gives both app and widget logs or asks for a before/after comparison.
7. Read `references/podhaven-log-format.md` only if you need field or truncation details.
8. Use `rg` on the raw file to zoom in on the relevant timestamps, levels, subsystems, or messages.
9. Report the time range, key problems, event timeline, and root-cause assessment with a clear separation between observation and inference.

## Workflow

### 1. Orient

- Run `python3 scripts/log_summary.py "$LOG_PATH"` to get the parsed entry count, Pacific Time range, level distribution, top sources and subsystems, and repeated warning or error messages.
- The filtered view collapses consecutive duplicate entries into short bursts by default so rapid-fire warnings stay readable. Use `--coalesce-window-ms 0` when you need every raw matching entry printed.
- The recurring issue section now groups by logger location, message, and metadata, and includes cadence plus common `NSURLErrorDomain` decoding.
- Treat the file as newline-delimited JSON. Do not dump a large log into context unless it is genuinely tiny.
- Present all user-facing timestamps in `America/Los_Angeles`.

### 2. Find candidate failures

- Prioritize `error` and `critical` entries.
- Include `warning` entries when they plausibly lead to a later failure or show repeated unhealthy behavior.
- Watch for repeated messages, bursts in the same time window, and the same `subsystem` or `category` appearing across multiple entries.

### 3. Reconstruct the timeline

- Search narrow time windows instead of scanning the full file.
- Use exact or prefix timestamp searches when you already know the relevant millisecond value.
- Correlate `source`, `subsystem`, `category`, `file`, `function`, and `metadata` to identify the code path and preconditions.
- Reformat multiline `message` values when quoting them. They are stored as escaped newlines inside JSON.

### 4. Correlate external references

- If the user gives a Sentry timestamp, convert it to milliseconds and inspect a narrow window around it with `python3 scripts/log_summary.py "$LOG_PATH" --around TIMESTAMP_MS --window-ms 30000`.
- If the user gives a subsystem, category, source file, or function name, prefer the dedicated flags before using `rg`.
- If the user gives multiple log files, analyze them separately first, then compare the timelines and crossover points.

## Commands

```bash
python3 scripts/log_summary.py "$LOG_PATH"
python3 scripts/log_summary.py "$LOG_PATH" --min-level error
python3 scripts/log_summary.py "$LOG_PATH" --min-level warning --coalesce-window-ms 0
python3 scripts/log_summary.py "$LOG_PATH" --subsystem Feed --category refreshManager --function refreshSeries
python3 scripts/log_summary.py "$LOG_PATH" --last-hours 6 --min-level warning
python3 scripts/log_summary.py "$LOG_PATH" --tail 200 --json
python3 scripts/log_summary.py "$LOG_PATH" --compare-other "$OTHER_LOG_PATH"
python3 scripts/log_summary.py "$LOG_PATH" --around 1768679500000 --window-ms 30000
python3 scripts/log_summary.py "$LOG_PATH" --match RefreshScheduler --min-level warning
rg -n '"level":(4|5|6)' "$LOG_PATH"
rg -n '"timestamp":17686795' "$LOG_PATH"
rg -n '"subsystem":"Play"|"category":"refreshScheduler"|"function":"refresh"' "$LOG_PATH"
```

## Reporting

- State the time range and timezone explicitly.
- Separate direct observations from inferred root cause.
- Quote only the minimum log text needed to support the conclusion.
- Mention possible missing lead-up context when the file appears truncated from the top.

## Resources

- Use `scripts/log_summary.py` for the first-pass summary and for focused time-window or text filtering.
- Use `scripts/log_summary.py` for the first-pass summary, structural filtering, recent-window scoping, JSON export, and cross-file comparison.
- Use `references/podhaven-log-format.md` for the exact entry schema, log file names, and truncation behavior.
