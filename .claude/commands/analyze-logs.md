---
description: Analyze PodHaven NDJSON log files
argument-hint: <path-to-log-file>
---

Analyze the log file at `$ARGUMENTS`.

## Log Format

The log file is NDJSON (newline-delimited JSON). Each line is a JSON object with these fields:

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | number | Milliseconds since Unix epoch |
| `levelName` | string | `debug`, `trace`, `info`, `warning`, `error` |
| `level` | number | 0=trace, 1=debug, 2=info, 3=warning, 5=error |
| `subsystem` | string | High-level category: `Play`, `Feed`, `Database`, `PodHaven`, `Cache` |
| `category` | string | Specific component: `manager`, `avPlayer`, `repo`, `refreshScheduler`, etc. |
| `message` | string | Log message (may be multi-line) |
| `function` | string | Function name that logged |
| `file` | string | Source file path |
| `line` | number | Line number in source |
| `source` | string | Always `PodHaven` |

## Timestamp Conversion

Convert timestamp to UTC date:
```bash
python3 -c "from datetime import datetime, UTC; print(datetime.fromtimestamp(TIMESTAMP_MS/1000, UTC).strftime('%Y-%m-%dT%H:%M:%S.000Z'))"
```

## Useful Queries

Search for errors/fatals:
```bash
grep -E '"level":[35]' <file> | head -50
```

Search by category:
```bash
grep '"category":"manager"' <file>
```

Search by function:
```bash
grep '"function":"handleMediaServicesReset' <file>
```

Get logs around a timestamp (within ~1 second):
```bash
grep -E '"timestamp":176867950' <file>
```

## Analysis Instructions

1. The log file may be large (>1MB). Use grep to search rather than reading the whole file.
2. When correlating with Sentry errors, convert the Sentry timestamp to milliseconds and search for nearby log entries.
3. Look for error-level logs (`level":5`) and trace the sequence of events leading up to them.
4. Pay attention to subsystem/category to understand which component logged each message.
5. Multi-line messages (stack traces, state dumps) are embedded in the `message` field with `\n` escapes.
