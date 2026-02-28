---
description: Analyze PodHaven NDJSON log files
argument-hint: <path-to-log-file>
context: fork
---

Analyze the log file at `$ARGUMENTS`.

## Log Format

The log file is NDJSON (newline-delimited JSON). Each line is a self-contained JSON object representing one log entry.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | number | Milliseconds since Unix epoch |
| `levelName` | string | `trace`, `debug`, `info`, `notice`, `warning`, `error`, `critical` |
| `level` | number | 0=trace, 1=debug, 2=info, 3=notice, 4=warning, 5=error, 6=critical |
| `subsystem` | string | High-level module (e.g. `Play`, `Feed`, `Database`, `PodHaven`, `Cache`, `PodHavenWidget`) |
| `category` | string | Specific component (e.g. `manager`, `avPlayer`, `repo`, `refreshScheduler`, `Widget`) |
| `message` | string | Log message (may contain `\n` for multi-line content like stack traces or state dumps) |
| `metadata` | object or null | Optional key-value pairs (`[String: String]`) attached by the logger for structured context |
| `function` | string | Swift function that emitted the log |
| `file` | string | Source file path |
| `line` | number | Line number in source file |
| `source` | string | Target that produced the entry (`PodHaven` or `PodHavenWidget`) |

## Analysis Instructions

Read and analyze the log file to answer the user's question. If no specific question was asked, provide a general diagnosis.

### Step 1 — Orient

1. Use the `Read` tool to read the **first 20 lines** and **last 20 lines** of the file to understand the time range and overall shape.
2. Convert the first and last timestamps to human-readable UTC dates. To convert: `timestamp / 1000` gives Unix seconds. You can compute the date mentally or use python:
   ```
   python3 -c "from datetime import datetime, UTC; print(datetime.fromtimestamp(TIMESTAMP_MS/1000, UTC))"
   ```
3. Note the time span covered and report it to the user.

### Step 2 — Find problems

1. Use the `Grep` tool (NOT bash grep) to search for errors and critical entries:
   - Pattern: `"level":[56]` — finds error (5) and critical (6) level entries
2. Also search for warnings if relevant: `"level":4`
3. Read the matching lines and surrounding context to understand what went wrong.

### Step 3 — Build the timeline

1. For each problem found, use `Grep` to find entries with nearby timestamps to reconstruct the sequence of events leading up to the error.
2. Pay attention to `subsystem` and `category` to understand which components were involved.
3. Check the `metadata` field for structured context that may explain the conditions.
4. Look for patterns: repeated errors, cascading failures, state transitions that precede the problem.

### Step 4 — Correlate

- If the user provides a Sentry error, timestamp, or other reference point, convert it to milliseconds and search for log entries in that time window.
- When looking at a specific time window, search for a timestamp prefix (e.g. `"timestamp":17686795` matches entries within ~10 seconds).
- Cross-reference subsystems to see if a failure in one component triggered issues in another.

### Step 5 — Report

Provide a clear summary including:
- **Time range** of the log file
- **Problems found** with timestamps and descriptions
- **Timeline** of events leading to each problem
- **Root cause** assessment if determinable
- **Relevant log excerpts** showing the key entries

## Tips

- Log files can be large (up to 2MB for main app, 500KB for widget). Always use `Grep` for searching — don't read the entire file.
- Multi-line messages (stack traces, state dumps) are embedded in the `message` field with `\n` escape sequences. Parse these to get readable output.
- The file is truncated from the top when it hits size limits, so the oldest entries may have been removed. The remaining entries still form a continuous timeline.
- Widget logs (`source: "PodHavenWidget"`) are in a separate file from main app logs.
