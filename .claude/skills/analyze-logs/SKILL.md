---
description: Analyze PodHaven NDJSON log files
argument-hint: <path-to-log-file>
---

Analyze the log file at `$ARGUMENTS`. If no file path was provided in the arguments, use the default path (the script knows it).

## Log Parser

This skill ships with `logparse.py` (located alongside this SKILL.md) which parses NDJSON log files into human-readable output with all timestamps in Pacific Time.

### Commands

```bash
# Overview: time range, entry counts by level, subsystem, category
python3 .claude/skills/analyze-logs/logparse.py summary

# Show warnings, errors, and critical entries (grouped by default)
python3 .claude/skills/analyze-logs/logparse.py errors
python3 .claude/skills/analyze-logs/logparse.py errors --min-level error
python3 .claude/skills/analyze-logs/logparse.py errors --no-group  # show every entry individually

# Filter entries by any combination of criteria
python3 .claude/skills/analyze-logs/logparse.py filter --subsystem Play --category avPlayer --tail -v
python3 .claude/skills/analyze-logs/logparse.py filter --min-level warning --after "2026-03-24 10:00" --before "2026-03-24 12:00"
python3 .claude/skills/analyze-logs/logparse.py filter --search "cache load failed" --limit 10 -v

# Show entries within a time window around a point
python3 .claude/skills/analyze-logs/logparse.py timeline "2026-03-24 09:48" --window 30
python3 .claude/skills/analyze-logs/logparse.py timeline 1774652894000 --window 60 --subsystem Play --min-level info --limit 20

# Detect app sessions (launch boundaries) with problem counts
python3 .claude/skills/analyze-logs/logparse.py sessions
```

Use `-f <path>` on any command to specify a non-default log file.

### Filter flags (all optional, combinable)

| Flag | Description |
|------|-------------|
| `--level <name\|num>` | Exact level match |
| `--min-level <name\|num>` | Minimum level (e.g. `warning`, `5`) |
| `--subsystem <name>` | Filter by subsystem (case-insensitive) |
| `--category <name>` | Filter by category (case-insensitive) |
| `--after <time>` | Only entries after this time |
| `--before <time>` | Only entries before this time |
| `--source <name>` | Filter by source (`PodHaven` or `PodHavenWidget`) |
| `--search <text>` | Case-insensitive message search |
| `--limit <n>` | Max entries to show (default 50, 0=all) |
| `--tail` | Show last N instead of first N |
| `-v` / `--verbose` | Include file, function, and metadata |

Time arguments accept: `YYYY-MM-DD HH:MM:SS`, `YYYY-MM-DD HH:MM`, `YYYY-MM-DD`, `MM/DD HH:MM`, or raw epoch milliseconds.

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

Use the log parser to answer the user's question. If no specific question was asked, provide a general diagnosis.

### Step 1 — Orient

Run `summary` and `sessions` to get the time range, entry counts, subsystem breakdown, and session boundaries. Report the time range and highlight any sessions with errors or warnings.

### Step 2 — Find problems

Run `errors` to see all warning/error/critical entries. If there are many, narrow with `errors --min-level error`.

### Step 3 — Build the timeline

For each problem found, use `timeline` centered on the error's timestamp to reconstruct the sequence of events. Use `--subsystem` to focus on the relevant component. Use `filter` with `--search` to find related entries across the full log.

### Step 4 — Correlate

- If the user provides a Sentry error, timestamp, or other reference point, use `timeline` centered on that point.
- Use `filter` to cross-reference subsystems and see if a failure in one component triggered issues in another.

### Step 5 — Report

Provide a clear summary including:
- **Time range** of the log file
- **Problems found** with timestamps and descriptions
- **Timeline** of events leading to each problem
- **Root cause** assessment if determinable
- **Relevant log excerpts** (paste formatted output from the parser)

## Tips

- Log files can be large (up to 2MB for main app, 500KB for widget). Always use the parser or `Grep` for searching — don't read the entire file.
- The file is truncated from the top when it hits size limits, so the oldest entries may have been removed. The remaining entries still form a continuous timeline.
- Widget logs (`source: "PodHavenWidget"`) are in a separate file from main app logs.
- If the parser output is very long, use `--limit` and `--tail` to focus on the most relevant entries.
