# PodHaven Log Format

Use this reference when you need exact field details or file-behavior context while analyzing `log.ndjson` or `widget-log.ndjson`.

## Files

- `log.ndjson`: main app log file. The app constructs this path from `AppInfo.logFileURL`.
- `widget-log.ndjson`: widget log file. The widget constructs this path from `WidgetInfo.logFileURL`.
- `/Users/jubi/Library/Mobile Documents/com~apple~CloudDocs/Podhaven Assets/log.ndjson`: common exported app log path used in the older Claude skill.

## Entry Schema

Each line is a standalone JSON object with these fields:

| Field | Type | Notes |
| --- | --- | --- |
| `level` | number | `0=trace`, `1=debug`, `2=info`, `3=notice`, `4=warning`, `5=error`, `6=critical` |
| `levelName` | string | Lowercase name of the log level |
| `timestamp` | number | Milliseconds since Unix epoch |
| `subsystem` | string | High-level module label |
| `category` | string | More specific logger category |
| `message` | string | Log message. May contain newline characters once decoded from JSON |
| `metadata` | object or null | Optional string key-value pairs |
| `source` | string | Target that emitted the entry, such as `PodHaven` or `PodHavenWidget` |
| `file` | string | Source file path reported by the logger |
| `function` | string | Swift function name |
| `line` | number | Source line number |

## Behavior

- The log format is NDJSON, not a JSON array. Parse one line at a time.
- `message` may decode to multiline text, including stack traces or state dumps.
- When the file exceeds its max size, PodHaven truncates from the top and keeps the newest complete lines.
- Truncation means the remaining file is still valid NDJSON, but older context may be missing.
- The file writer appends a newline after every encoded entry.

## Analysis Notes

- Start with counts and repeated warnings or errors before reading individual entries.
- Prefer structural filters such as subsystem, category, source file, and function before broad text matching.
- Use recent scopes like `--last-hours` or `--tail` when the user only cares about the latest failure window.
- Compare logs side-by-side when the user provides both app and widget files.
- Use timestamps, `subsystem`, `category`, `source`, and `metadata` together to reconstruct the event chain.
- Present user-facing timestamps in Pacific Time unless the user explicitly asks for another timezone.
