---
name: analyze-logs
description: Analyze PodHaven logs and reconstruct failure timelines from the NDJSON file logs and/or the OS unified log (os_log / Console). Use when inspecting log.ndjson, widget-log.ndjson, or their recent-log attachments, capturing os_log/Console output from the Simulator or the My Mac (macDev) build, diagnosing warnings or errors, correlating a Sentry timestamp to local logs, or explaining what happened around a specific time, subsystem, category, source file, or message.
disable-model-invocation: false
---

# Analyze Logs

Reconstruct what happened from PodHaven's local logs: the NDJSON file logs and the OS unified log. Sentry's structured logs belong to `analyze-sentry-logs`; `analyze-sentry-issue` and `analyze-sentry-feedback` download event and feedback attachments and hand their paths to this skill's scripts.

## The user names the source

Never infer or auto-select a log. Ask which run the user reproduced, such as the Simulator, My Mac, a device export, or a Sentry or feedback attachment, and whether they want the file log, the unified log, or both, and get a concrete file path before analyzing a file. `scripts/locate_logs.py` lists the usual locations to help them find it but chooses none. A path an invoking skill passes, such as a downloaded attachment, counts as the user's. Repeat the path and run context back in your first analysis message.

## NDJSON file logs

All Development runs on one destination, from every worktree, append to one rolling `log.ndjson`, so find the user's launch by its time, build, and commit in `--sessions`. On the Simulator, Settings → Debug → Share Logs saves the file to the Mac's `~/Desktop`.

Analyze with `scripts/log_summary.py "$LOG_PATH"`, whose `--help` gives its scope, filter, and display flags and the time formats they accept, rather than reading a multi-megabyte file into context:

1. Start with no filters for the overview, then scope a rolling log to one launch with `--session N`.
2. Prioritize `error` and `critical`, with relevant warnings; `--call-sites` finds storms that never reach warning level.
3. Build the timeline with `--around`, which takes a Sentry timestamp as is, or `--after`/`--before`; prefer structural filters, such as `--subsystem`, `--category`, `--file`, and `--function`, to `--match`, and use `rg` on the raw file for line-level detail.
4. Analyze app and widget logs separately, then compare them with `--compare-other`.
5. Resolve a MetricKit diagnostic's call stack with `scripts/symbolicate_metrickit.py`.

[The log format](references/podhaven-log-format.md) gives the entry fields, how each file is truncated and rate-limited, and MetricKit entries.

## OS unified log

PodHaven mirrors every swift-log entry to the unified log in Simulator, My Mac, and device builds, interleaved with the system and framework events, such as XPC, AVFoundation, and networking, that the file log never captures: use it when the OS is in the failure path. Unlike the file log, it isn't rate-limited, but it carries only each entry's message, without metadata or call site. Triage the file log with `log_summary.py`, then pull the same window from the unified log with `log show --start/--end`.

- Filter by process: `PodHaven` on the Simulator and My Mac alike. The extensions run as `PodHavenWidget`, `PodHavenShare`, and `PodHavenIntents`, and the last two log only here. Subsystems share no prefix: each is a `LogSubsystem` type's name, such as `Feed` or `Play`, `PodHaven` for `Log.as("…")` string loggers, or `PodHavenShare` for the share extension. A subsystem filter misses string loggers, in the file log too.
- Levels remap: trace and debug to `Debug`, info to `Info`, notice to `Default`, warning and error to `Error`, and critical to `Fault`, so predicate on `messageType`.
- `log show` and `log stream` hide `Debug` and `Info` without `--info --debug`, and most app entries are debug.
- Messages are public, never `<private>`.
- Call `/usr/bin/log`, since zsh's `log` builtin shadows a bare `log`.

```bash
# My Mac (macDev): stream live, or `show --last 30m` with the same flags
/usr/bin/log stream --info --debug --style compact \
  --predicate 'process == "PodHaven" AND eventType == "logEvent" AND NOT subsystem BEGINSWITH "com.apple"'

# Keep a capture to query again, since the live buffer rolls
/usr/bin/log collect --last 30m --output /tmp/podhaven-mymac.logarchive
/usr/bin/log show /tmp/podhaven-mymac.logarchive --info --debug --style compact \
  --predicate 'process == "PodHaven" AND eventType == "logEvent" AND NOT subsystem BEGINSWITH "com.apple"'

# Simulator
xcrun simctl spawn booted log show --last 30m --info --debug --style compact \
  --predicate 'process == "PodHaven" AND eventType == "logEvent" AND NOT subsystem BEGINSWITH "com.apple"'
```

Drop the `com.apple` exclusion to see the surrounding framework events; keeping it is best-effort, since other framework subsystems, such as `IOSurface`, still slip through. `--style ndjson` emits JSON for `jq`.

## Reporting

State the log path and run context as given, the time range and its zone, observations apart from inferred root cause, and any lead-up lost to truncation.
