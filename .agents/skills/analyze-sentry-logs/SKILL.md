---
name: analyze-sentry-logs
description: >
  Analyze Sentry logs to find real issues, severity mismatches, and missing observability.
  Only runs when explicitly invoked via /analyze-sentry-logs.
allowed-tools: Bash, Read, Grep, Glob, Agent
disable-model-invocation: true
---

# Sentry Log Analysis

Analyze Sentry logs for the PodHaven iOS app. This is a **logs-only** analysis — no Sentry issues, events, crashes, or other data. Focus exclusively on what the logs reveal.

## Arguments

Accepts a time span argument. Examples:
- `/analyze-sentry-logs 12h` — last 12 hours
- `/analyze-sentry-logs 2d` — last 2 days
- `/analyze-sentry-logs 1w` — last week

**If no argument is provided, ask the user what time span they want before proceeding.**

## Prerequisites

Requires `~/.sentryclirc` with a valid auth token. If the fetch script fails with an auth error, tell the user to run `! sentry-cli login`.

## Step 1: Fetch logs

Run the fetch script at `~/.claude/skills/analyze-sentry-logs/fetch_sentry_logs.sh`. It queries the Sentry REST API directly (not sentry-cli, which deduplicates entries) and produces two JSON files:

```bash
bash ~/.claude/skills/analyze-sentry-logs/fetch_sentry_logs.sh <statsPeriod>
```

Where `<statsPeriod>` matches the user's time span (e.g., `10h`, `2d`, `1w`).

This outputs:
- `/tmp/sentry_logs_detail.json` — individual log entries with timestamps (up to 500)
- `/tmp/sentry_logs_summary.json` — aggregated counts grouped by severity + message
- A summary table printed to stdout

Present the summary table to the user immediately.

If you need to inspect individual entries (e.g., timestamps, burst patterns), read the detail JSON:
```bash
python3 -c "
import json
with open('/tmp/sentry_logs_detail.json') as f:
    for row in json.load(f)['data']:
        print(f\"{row['timestamp']}\t{row['severity']}\t{row['message'][:120]}\")
"
```

## Step 2: Deep-dive into every log pattern

For **every unique log pattern** in the summary, find the source code. Use Grep to locate the log message string in `*.swift` files, then Read the surrounding context (at least 15 lines in each direction).

For each pattern, determine:

1. **What triggers this log?** Read the function it's in. What condition leads here? Trace callers if needed.
2. **Is this expected or a bug?** Is this a normal edge case the code handles gracefully, or does it indicate a real problem the user should know about?
3. **Is the severity right?**
   - `.error`: something is broken and needs investigation
   - `.warning`: something unexpected happened but was handled
   - `.info`: notable state change, useful context
   - `.debug`: verbose detail for active debugging only
4. **Is there enough context in the log message?** Look at the local variables available at the log call site. Could you diagnose the root cause from this message alone, or is it missing values that are right there in scope? For example, a guard that logs "value is invalid" should include what the value actually was. Recommend adding specific variables/state to the message string.
5. **Are related failure modes unlogged?** Look at nearby code paths — are there error conditions or edge cases with no logging at all?
6. **Burst patterns** — If the same message fires multiple times within milliseconds, investigate why. Check the detail JSON timestamps to identify bursts. This often reveals a single event triggering multiple redundant log calls.

For logs produced by `caughtError()` (which uses `ErrorKit.isRemarkable()` to choose between `remarkable:` and `mundane:` severity levels), check whether the error type is correctly classified. `isRemarkable` should return false for expected errors like cancellation, network timeouts, etc.

For log messages **not found** in the current codebase, check `git log --oneline -10` for recent refactors that may have removed them. Mark these as **Stale** and skip deep analysis — they'll stop once users update.

## Step 3: Classify each pattern

Every log pattern gets exactly one verdict:

- **Real issue** — The log reveals a bug, data problem, or user-facing degradation. Describe what's wrong and suggest a fix.
- **Downgrade to `.X`** — Fires for an expected/handled condition. Specify current and recommended level, and why.
- **Upgrade to `.X`** — Fires for something more serious than its level suggests. Specify current and recommended level, and why.
- **Enrich message** — The log fires at the right level but is missing context that's available in scope. Specify what variables/state to add to the message string.
- **Add logging** — A nearby code path lacks observability. Describe what to add, at what level, and where.
- **Fine as-is** — Right level, useful signal, sufficient context. Briefly say why.
- **Stale** — From code no longer in the codebase. Skip.

## Report Format

```
# Sentry Log Analysis — [time span] ([absolute date range in PT])

## Summary
[2-3 sentences: total log count by severity in the time window, overall signal-to-noise assessment]

## Log Patterns

Present every unique log pattern, in descending order of count:

### `[first line of message]`
- **Count:** N | **Severity:** error/warn | **Source:** `File.swift:LINE`
- **Verdict:** Real issue | Downgrade to .X | Upgrade to .X | Add logging | Fine as-is | Stale
- **Analysis:** [What triggers this, why it fires at this frequency, what should change and why.
  For "Real issue" verdicts: describe the bug and suggest a fix.
  For severity changes: explain what signal is gained or noise removed.
  For "Add logging": describe the gap and what to add.]
- **Suggested change:** [Specific code diff if applicable, or "None"]

## Missing Observability
[Code paths found during the deep-dive that should have logging but don't.
 Only include concrete gaps — not hypothetical ones.]
[If none: omit this section]
```

Keep it dense and actionable. Every pattern gets a verdict. No filler.
