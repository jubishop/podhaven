# PodHaven Log Format

Use this reference when you need exact field details or file-behavior context while analyzing `log.ndjson` or `widget-log.ndjson`.

## Files

- `log.ndjson`: main app log file. The app constructs this path from `AppInfo.logFileURL`.
- `widget-log.ndjson`: widget log file. The widget constructs this path from `WidgetInfo.logFileURL`.

### Where files live on the Mac host

Development (Run / `.dev` bundle) — **one rolling file per destination** (all worktrees share it):

| Destination | App log | Widget log |
|-------------|---------|------------|
| Booted Simulator | `$DATA/Documents/PodHavenDev/log.ndjson` where `DATA=$(xcrun simctl get_app_container booted com.artisanalsoftware.PodHaven.dev data)` | `$GROUP/widget-log.ndjson` where `GROUP=$(xcrun simctl get_app_container booted com.artisanalsoftware.PodHaven.dev group.podhaven.shared.dev)` |
| My Mac | `~/Library/Containers/com.artisanalsoftware.PodHaven.dev/Data/Documents/PodHavenDev/log.ndjson` | `~/Library/Group Containers/group.podhaven.shared.dev/widget-log.ndjson` |

Production (Release bundle): `Documents/log.ndjson` (no `PodHavenDev` subdir) under the production container; app group `group.podhaven.shared`.

The analyze-logs skill requires the user to supply the path explicitly. Run `scripts/locate_logs.py` for a reference list only — it does not choose a file.

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

Release-build binaries are stripped and the dSYM never ships to device, so the frames are **unsymbolicated**: each carries `binaryUUID` + `offsetIntoBinaryTextSegment` but no function/file/line. Use `scripts/symbolicate_metrickit.py` to resolve them against dSYMs from Sentry's Debug Files API.

The `MetricKit` background-exit metrics directive (separate, `.info` or `.critical`) uses a different shape: per-reason exit counts live as flat string keys in metadata (`normalAppExit`, `memoryResourceLimit`, …) and there is no `metricKitDiagnostic` field. The symbolication script ignores those.

## Analysis Notes

- Start with counts and repeated warnings or errors before reading individual entries.
- Prefer structural filters such as subsystem, category, source file, and function before broad text matching.
- Use recent scopes like `--last-hours` or `--tail` when the user only cares about the latest failure window.
- Compare logs side-by-side when the user provides both app and widget files.
- Use timestamps, `subsystem`, `category`, `source`, and `metadata` together to reconstruct the event chain.
- Present user-facing timestamps in Pacific Time unless the user explicitly asks for another timezone.
- When a MetricKit entry surfaces in the timeline, run `scripts/symbolicate_metrickit.py` against the same NDJSON to resolve the call stack instead of staring at raw `binaryUUID+offset` frames.
