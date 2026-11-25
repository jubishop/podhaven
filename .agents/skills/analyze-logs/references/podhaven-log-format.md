# PodHaven Log Format

## Files

| File | Written by | Holds |
| --- | --- | --- |
| `log.ndjson` | App, at `AppInfo.logFileURL` | The newest entries across launches |
| `widget-log.ndjson` | Widget, at `WidgetInfo.logFileURL` | The same, for the widget |
| `recent-log.ndjson`, `recent-widget-log.ndjson` | App and widget, at each one's `recentLogFileURL` | A small tail of earlier launches plus the current launch's newest entries; Sentry events attach them |

## Entry Schema

Each line is a standalone JSON object with these fields:

| Field | Type | Notes |
| --- | --- | --- |
| `level` | number | `0=trace`, `1=debug`, `2=info`, `3=notice`, `4=warning`, `5=error`, `6=critical` |
| `levelName` | string | Lowercase name of the log level |
| `timestamp` | number | Milliseconds since Unix epoch |
| `subsystem` | string | High-level module label |
| `category` | string | More specific logger category |
| `message` | string | May decode to multiline text, such as a stack trace or state dump |
| `metadata` | object or null | Optional string key-value pairs |
| `source` | string | Target that emitted the entry, such as `PodHaven` or `PodHavenWidget` |
| `file` | string | Source file path reported by the logger |
| `function` | string | Swift function name |
| `line` | number | Source line number |
| `sessionID` | string | One UUID per process launch |
| `version`, `buildNumber`, `gitCommitHash` | string | The build that wrote the entry |

## Behavior

- When a file exceeds its max size, PodHaven truncates it from the top, keeping complete lines, so the rest is valid NDJSON but older context may be missing. The truncation notice goes only to the unified log. The recent-log files keep their earlier-launch tail through truncation.
- The file logs rate-limit each call site, its `file` and `line`, after a burst; the unified log gets every entry. An `info` entry, `FileLogHandler admission limit — dropped N entries from this log site`, records each drop, so counts by call site understate a storm by those N.
- The recent-log files cap each entry's size: an oversized entry keeps a prefix of its message, and its metadata becomes `fileLog.originalRecordBytes` and `fileLog.recordLimitBytes`.

## MetricKit Diagnostic Entries

Each MetricKit diagnostic is a `notice` entry in category `MetricKit` with the message `MetricKit <category> diagnostic received` and the raw `MXDiagnosticPayload.jsonRepresentation()`, as a string, in `metadata.metricKitDiagnostic`. Its frames carry only binary UUIDs and offsets, which `scripts/symbolicate_metrickit.py` resolves.

The foreground- and background-exit metrics entries, in the same category, carry flat per-reason counts in metadata, such as `normalAppExit` and `memoryResourceLimit`, instead of a diagnostic payload.
