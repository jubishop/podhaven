# PodHaven Log Format

Use this reference when you need exact field details or file-behavior context while analyzing PodHaven's NDJSON logs. `scripts/locate_logs.py` lists where they live on this Mac.

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
| `message` | string | Log message. May contain newline characters once decoded from JSON |
| `metadata` | object or null | Optional string key-value pairs |
| `source` | string | Target that emitted the entry, such as `PodHaven` or `PodHavenWidget` |
| `file` | string | Source file path reported by the logger |
| `function` | string | Swift function name |
| `line` | number | Source line number |
| `sessionID` | string | One UUID per process launch |
| `version`, `buildNumber`, `gitCommitHash` | string | The build that wrote the entry |

## Behavior

- The log format is NDJSON, not a JSON array. Parse one line at a time.
- `message` may decode to multiline text, including stack traces or state dumps.
- When a file exceeds its max size, PodHaven truncates it from the top, keeping complete lines, so the rest is valid NDJSON but older context may be missing. The truncation notice goes only to the unified log. The recent-log files keep their earlier-launch tail through truncation.
- The file logs rate-limit each call site, its `file` and `line`, after a burst; the unified log gets every entry. An `info` entry, `FileLogHandler admission limit — dropped N entries from this log site`, records each drop, so counts by call site understate a storm by those N.
- The recent-log files cap each entry's size: an oversized entry keeps a prefix of its message, and its metadata becomes `fileLog.originalRecordBytes` and `fileLog.recordLimitBytes`.

## MetricKit Diagnostic Entries

`MetricKitMonitor.diagnosticDirective` writes one log entry per `MXDiagnostic` payload (crash, hang, cpuException, diskWriteException, appLaunch). They show up with:

- `subsystem`: `PodHaven`
- `category`: `MetricKit`
- `levelName`: `notice`
- `message`: `MetricKit <category> diagnostic received` — e.g. `MetricKit crash diagnostic received`. The token after `MetricKit ` is the category (one of `crash`, `hang`, `cpuException`, `diskWriteException`, `appLaunch`).
- `metadata.metricKitDiagnostic`: the **raw** `MXDiagnosticPayload.jsonRepresentation()` JSON, encoded as a string. It is **not** parsed into structured metadata — it is kept verbatim so the call-stack tree stays machine-parseable for offline symbolication.

The embedded JSON is shaped like:

```json
{
  "callStackTree": {
    "callStackPerThread": false,
    "callStacks": [
      {
        "threadAttributed": true,
        "callStackPerThread": false,
        "callStackRootFrames": [
          {
            "binaryUUID": "ABCDEF12-3456-7890-ABCD-EF1234567890",
            "offsetIntoBinaryTextSegment": 12345,
            "binaryName": "PodHaven",
            "sampleCount": 1,
            "subFrames": [ /* same frame shape, recursive */ ]
          }
        ]
      }
    ]
  },
  "diagnosticMetaData": {
    "platformArchitecture": "arm64e",
    "appVersion": "1.0",
    "appBuildVersion": "498",
    "osVersion": "iPhone OS 18.0 (22A123)",
    /* category-specific fields: terminationReason, signal, hangDuration, etc. */
  }
}
```

Release-build binaries are stripped and the dSYM never ships to device, so the frames are **unsymbolicated**: each carries `binaryUUID` + `offsetIntoBinaryTextSegment` but no function/file/line. Use `scripts/symbolicate_metrickit.py` to resolve them against dSYMs from Sentry's Debug Files API. The script also accepts one downloaded raw diagnostic file, such as the `metrickit-crash-diagnostic.json` attachment on a forwarded MetricKit crash event or the SDK's `MXDiagnosticPayload.json`; that file has no log timestamp, so `--around` excludes it.

The foreground- and background-exit metrics entries, also in category `MetricKit`, use a different shape: per-reason exit counts live as flat string keys in metadata (`normalAppExit`, `memoryResourceLimit`, …) and there is no `metricKitDiagnostic` field. The symbolication script ignores those.
