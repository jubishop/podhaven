---
name: analyze-logs
description: Analyze PodHaven logs and reconstruct failure timelines from the NDJSON file logs and/or the OS unified log (os_log / Console). Requires the user to specify the log source and run context (do not infer). Use when inspecting log.ndjson or widget-log.ndjson, capturing os_log/Console output from the Simulator or the My Mac (macDev) build, diagnosing warnings or errors, correlating a Sentry timestamp to local logs, or explaining what happened around a specific time, subsystem, category, source file, or message.
user_invocable: true
---

# Analyze Logs

Inspect PodHaven NDJSON logs without reading the entire file into context. Use the bundled summary script for structured analysis, then targeted `rg` searches when you need line-level confirmation.

Scope: this skill covers **local** logs — the NDJSON file logs and the OS unified log (os_log/Console). Sentry's **structured logs** (`ourlogs`) are a different source; use `analyze-sentry-logs` for those. Sentry event/feedback NDJSON **attachments** are fetched by `analyze-sentry-issue` / `analyze-sentry-feedback`, which then hand the downloaded files back to this skill's scripts.

## Required: user must say where the logs are

**Do not infer or auto-select a log path.** Before running `log_summary.py` or reading a file:

1. **Ask the user** which run they reproduced (Simulator, My Mac, physical device export, path they copied, attachment from feedback/Sentry, etc.).
2. **Require a concrete path** (or a clear copy destination they name, e.g. `/tmp/podhaven-log.ndjson`).
3. **Repeat back** the path and run context in your first analysis message.

If the user has not supplied a path, stop and ask. You may run `scripts/locate_logs.py` only to show **reference** locations while waiting — that script does not choose a file for you.

A concrete path supplied by an invoking skill counts as user-supplied — e.g. the `analyze-sentry-issue` / `analyze-sentry-feedback` flows pass the paths of the reporter's downloaded attachments. Repeat the path and its run context back and proceed; do not re-ask.

## Reference: where logs usually live (confirm with the user)

Use this table to help the user find files; **do not analyze until they confirm the path.**

| Run context | App log (`log.ndjson`) | Widget log (`widget-log.ndjson`) |
|-------------|------------------------|----------------------------------|
| **iOS Simulator** (Development / Run) | `<sim-data>/Documents/PodHavenDev/log.ndjson` | `<sim-group>/widget-log.ndjson` |
| **My Mac** (`macDev` — Xcode "My Mac" run; Mac Catalyst / iOS-app-on-Mac, `.dev`) | `~/Library/Containers/com.artisanalsoftware.PodHaven.dev/Data/Documents/PodHavenDev/log.ndjson` | `~/Library/Group Containers/group.podhaven.shared.dev/widget-log.ndjson` |
| **Physical iPhone** (dev) | User must Share/Save or copy via Finder/device tools — **ask for the saved path** | Same; separate widget file |
| **Production** (Release) | `~/Library/Containers/com.artisanalsoftware.PodHaven/Data/Documents/log.ndjson` | `~/Library/Group Containers/group.podhaven.shared/widget-log.ndjson` |

**Simulator — copy to Mac host** (after user confirms they reproduced on Simulator):

```bash
DATA="$(xcrun simctl get_app_container booted com.artisanalsoftware.PodHaven.dev data)"
cp "$DATA/Documents/PodHavenDev/log.ndjson" /tmp/podhaven-log.ndjson
# Give /tmp/podhaven-log.ndjson (or another path the user chooses) to analysis.
```

Share sheet on **Simulator does not export to the Mac** — `simctl` copy or an explicit path the user provides.

**Reference listing** (no path selection):

```bash
python3 scripts/locate_logs.py
python3 scripts/locate_logs.py --widget
python3 scripts/log_summary.py --list-locations
```

### Rolling buffer and worktrees

- All **Development** runs on the same simulator (or same My Mac container) append to **one** `log.ndjson`.
- Worktrees do not create separate log files.
- After repro, user should **copy immediately** or you scope with `--sessions` and match **Settings → Git** / `Git commit hash is:` in the log.

## OS unified logs (os_log / Console)

PodHaven mirrors **every** swift-log entry to the OS unified log via `OSLogHandler`, alongside the NDJSON file. Active in `.simulator`, `.iPhoneDev`, `.macDev`, and deployed builds (not `.preview` / `.testing`). The unique value over the file log: the app's own entries arrive **interleaved with system/framework events** (XPC, AVFoundation, networking, SkyLight) that the NDJSON never captures — use it when the OS, not just app code, is in the failure path.

Same rule as the file logs: **ask which run the user reproduced; do not infer.** The "My Mac" run is the `macDev` environment (`isMacCatalystApp || isiOSAppOnMac`) and runs as a native Mac process named `PodHaven` on this host.

### How PodHaven maps onto the unified log

- **Subsystem is the swift-log label prefix, not a bundle id.** Each `LogCategorizable` enum is its own subsystem equal to the enum's type name — `Feed`, `Play`, `Cache`, `Database`, `Recommendations`, `State`, `PlayBar`, `SearchView`, `Widget`, etc. Default `Log.as(String)` loggers use `PodHaven`; the share extension uses `PodHavenShare`. There is **no shared `com.apple`-style prefix**, so filter by **process**, not subsystem.
- **Process name is `PodHaven`** (Simulator and My Mac alike). Only one PodHaven run exists at a time, so the process filter is unambiguous regardless of branch/worktree.
- **Level remap** (`OSLogHandler`): swift-log `trace`/`debug` → `Debug`, `info`/`notice` → `Info`, `warning`/`error` → `Error`, `critical` → `Fault`. So a swift-log **warning surfaces as an `Error`-type** unified entry and a **critical as `Fault`** — predicate on `messageType`, not the original swift-log name.
- **`log show` hides `Debug`/`Info` by default.** Most app entries are `.debug`, so pass `--info --debug` or you'll see almost nothing.
- Messages emit with `privacy: .public` — never redacted to `<private>`.
- If a bare `log` command errors with `too many arguments`, a shell function is shadowing it — call `/usr/bin/log` explicitly.

### Capture — My Mac (`macDev`) on this host

```bash
# Live tail (Ctrl-C to stop); historical via `log show --last 30m` with the same flags
/usr/bin/log stream --info --debug --style compact \
  --predicate 'process == "PodHaven" AND eventType == "logEvent" AND NOT subsystem BEGINSWITH "com.apple"'

# Permanent artifact you can re-query offline, like a file
/usr/bin/log collect --last 30m --output /tmp/podhaven-mymac.logarchive
/usr/bin/log show /tmp/podhaven-mymac.logarchive --info --debug --style compact \
  --predicate 'process == "PodHaven" AND eventType == "logEvent" AND NOT subsystem BEGINSWITH "com.apple"'
```

Drop `AND NOT subsystem BEGINSWITH "com.apple"` to **include** surrounding framework/system events; keep it to see (almost) only PodHaven's own log statements — the exclusion is best-effort, so a few non-Apple framework subsystems (e.g. `IOSurface`) still slip through. `--style ndjson` (or `json`) emits machine-readable output for `jq`.

### Capture — Simulator

Scope `log` to the booted simulator with `simctl spawn booted`; the in-sim process is also named `PodHaven`:

```bash
xcrun simctl spawn booted log show --last 30m --info --debug --style compact \
  --predicate 'process == "PodHaven" AND eventType == "logEvent" AND NOT subsystem BEGINSWITH "com.apple"'
```

### Analyze NDJSON + unified log in tandem

Both carry the same `subsystem`, `category`, and message text, so they align by timestamp:

- Run `log_summary.py` on the **NDJSON** for structured triage (sessions, call-sites, level families, `--around`) — it also has `source`/`file`/`function`/`line`/`metadata` the unified message text lacks.
- Pull the matching window from the **unified log** (`log show --start/--end`, or `--last`) to see what the OS was doing at the same instant — the file log can't show that.
- Unified-log timestamps print in the host's local zone; report in Pacific (as with the file logs).
- Save a `.logarchive` when you'll re-query the same capture more than once; the live buffer is rolling and system-wide.

## Quick Start

1. **Get path from the user** — mandatory; no defaults.
2. Run `python3 scripts/log_summary.py "$LOG_PATH"` with no filters for the initial overview.
3. Add structural filters (`--subsystem`, `--category`, `--source`, `--file`, `--function`) before falling back to broad `--match`.
4. Use `--last-hours`, `--tail`, `--after`/`--before` to narrow time ranges.
5. Use `--sessions` to find app launch boundaries, then `--session N` to scope every later command to one launch.
6. Use `--call-sites`, `--oneline`, `--json`, `--compare-other` as needed.
7. Use `rg` on the raw file for line-level precision.
8. Read `references/podhaven-log-format.md` for field or truncation details.

## Commands

```bash
# Reference only — does not pick a log file
python3 scripts/locate_logs.py

# Analysis — LOG_PATH must come from the user
python3 scripts/log_summary.py "$LOG_PATH"
python3 scripts/log_summary.py "$LOG_PATH" --sessions
python3 scripts/log_summary.py "$LOG_PATH" --session 12 --call-sites

python3 scripts/log_summary.py "$LOG_PATH" --min-level warning --last-hours 6
python3 scripts/log_summary.py "$LOG_PATH" --around '2026-06-12T16:26:55Z' --window-ms 30000
python3 scripts/log_summary.py "$LOG_PATH" --subsystem Feed --category refreshManager
python3 scripts/log_summary.py "$LOG_PATH" --match "cache load failed" --min-level warning
python3 scripts/log_summary.py "$LOG_PATH" --tail 200 --json
python3 scripts/log_summary.py "$LOG_PATH" --compare-other "$WIDGET_LOG_PATH"

rg -n '"level":(4|5|6)' "$LOG_PATH"
python3 scripts/symbolicate_metrickit.py "$LOG_PATH"
```

## Flags Reference

### Scope (narrows the active view before analysis)
| Flag | Description |
|------|-------------|
| `--after TIME` | Only entries after this time (datetime string or epoch ms) |
| `--before TIME` | Only entries before this time |
| `--last-hours N` | Restrict to entries within N hours of the latest entry |
| `--tail N` | Keep only the last N entries after other scope filters |
| `--session N` | Restrict to a single detected session by number (see `--sessions`) |

Time arguments accept: `YYYY-MM-DD HH:MM:SS`, `YYYY-MM-DD HH:MM`, `YYYY-MM-DD`, `MM/DD HH:MM`, ISO-8601 with optional timezone (e.g. `2026-06-12T16:26:55Z` — paste Sentry timestamps directly), or raw epoch milliseconds. Times without a timezone are interpreted as Pacific. The same formats work for `symbolicate_metrickit.py --around`.

### Selection filters (choose which entries to display)
| Flag | Description |
|------|-------------|
| `--min-level LEVEL` | Minimum level: trace, debug, info, notice, warning, error, critical |
| `--around TIME` | Select entries within `--window-ms` of this time (same formats as `--after`/`--before`) |
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
| `--call-sites` | Print a histogram of the selection grouped by `file:line` + function |
| `--oneline` | Print each selected entry as one dense line instead of the multi-line block |
| `--compare-other PATH` | Compare the primary log to another log using the same filters |
| `--list-locations` | Print reference log locations and exit (same as `locate_logs.py`) |

## Workflow

### 0. Obtain source (mandatory)

- Ask: Simulator, My Mac (`macDev`), device copy, Sentry/feedback attachment, or other? And which surface — NDJSON file log, OS unified log (os_log/Console), or both?
- For a file log, do not run analysis until the user supplies or confirms a filesystem path. Optionally show `locate_logs.py` output to help; still require confirmation.
- For the unified log, confirm the run context, then capture live/historical per "OS unified logs" above (process `PodHaven`; pass `--info --debug`).

### 1. Orient

- Run `log_summary.py "$LOG_PATH"` with no filters.
- Use `--sessions` for rolling-buffer logs spanning many launches.
- Present user-facing timestamps in Pacific Time.

### 2. Find candidate failures

- Prioritize `error` and `critical`; include relevant `warning` entries.
- Use `--call-sites` for chattiness without high severity.

### 3. Reconstruct the timeline

- `--around`, `--after`/`--before`, structural filters, then `rg` as needed.

### 4. Correlate external references

- Sentry timestamp → paste directly into `--around` (ISO-8601 with timezone accepted; epoch ms too).
- Multiple files → separate analysis, then `--compare-other`.

### 5. Symbolicate MetricKit call stacks

- See `references/podhaven-log-format.md` and `scripts/symbolicate_metrickit.py`.

## Reporting

- State **log path and run context** as given by the user.
- State time range and timezone (Pacific unless asked otherwise).
- Separate observations from inferred root cause.
- Note truncation / missing lead-up when the file was trimmed from the top.

## Resources

- `scripts/locate_logs.py` — reference list of common host paths (does not select a file)
- `scripts/log_summary.py` — primary analysis tool (requires explicit path)
- `scripts/symbolicate_metrickit.py` — MetricKit symbolication
- `references/podhaven-log-format.md` — entry schema and truncation behavior
