---
name: analyze-sentry-feedback
description: >-
  Triage a Sentry user feedback item end to end: fetch the feedback, download
  the reporter's NDJSON logs (app and widget) that PodHaven attaches to the
  feedback event, correlate them to the report time, and explain what likely
  happened plus a suggested fix. Use when the user pastes a Sentry feedback
  URL (e.g. .../issues/feedback/?feedbackSlug=podhaven:NNN...), references a
  feedback by slug or ID, or asks to investigate a piece of user feedback
  from Sentry.
user_invocable: true
disable-model-invocation: true
argument: >-
  A Sentry feedback URL, a feedbackSlug like `podhaven:7485822944`, or a bare
  numeric feedback ID. Any additional free-text the user types alongside that
  reference (hunches, context, focus areas, "ignore X", "this user is on beta",
  etc.) should be treated as triage instructions and surfaced in the report.
  If no reference is provided, ask the user for one before proceeding.
---

# Analyze Sentry Feedback

Triage a single Sentry user feedback report by combining the Sentry side (the
feedback text, contact info, replay/event/trace links, timestamp) with the
NDJSON logs the iOS app and widget attach directly to the feedback event in
Sentry. Those attachments are the *reporter's* logs and the only logs that
correctly correspond to the report — not the developer's local iCloud Drive
copies.

The goal is one focused report: what the user complained about, what the logs
around that time show, the most likely root cause, and how to fix it.

## Scope

One feedback at a time. Do **not** use this skill to summarize many feedbacks
at once or to do general Sentry log triage — for that, use
`analyze-sentry-logs`.

## Step 1: Parse the reference and the user's own notes

From the argument, extract:

1. **Feedback slug**: prefer the value of `feedbackSlug=` in the URL (URL-decode
   it). If only a numeric ID is provided, assume the slug is `podhaven:<id>`.
2. **Numeric feedback ID**: the part after `:` in the slug.
3. **Sentry org**: `artisanal-software` (default for this repo).
4. **Project ID**: `4508469264711681` if present in the URL, else assume the
   PodHaven project.
5. **User notes alongside the link**: any free-text the user typed in the same
   argument that isn't part of the URL/slug. Treat it as triage instructions
   (e.g. "I think this is the search bug from last week", "ignore the widget
   side", "user is on TestFlight build 412"). Carry these notes forward — they
   shape what to focus on in Steps 4–6 and must appear verbatim in the report.

Tell the user the parsed slug in one short line before fetching, so they can
catch a mis-paste early. If the user attached notes, echo them back in the
same line so they know they were picked up (not silently dropped).

## Step 2: Fetch the feedback from Sentry

Requires the **`sentry` CLI** and auth (`sentry auth login`). See
`analyze-sentry-issue` prerequisites for install notes. Do not use the Sentry MCP
server.

Run:

```bash
bash .agents/skills/sentry-cli/fetch_feedback_bundle.sh <slug> \
  --out /tmp/sentry_feedback
```

This writes:

- `/tmp/sentry_feedback/issue.json` — feedback title, metadata (message, contact)
- `/tmp/sentry_feedback/event_<id>.json` — full event (tags, contexts, breadcrumbs)
- `/tmp/sentry_feedback/activities.json` — issue activity stream
- `/tmp/sentry_feedback/notes.json` — owner notes/comments (may be empty)
- `/tmp/sentry_feedback/attachments.json` — attachment metadata

Read those files for:

- The user's original free-text message (`issue.metadata.message` or event contexts)
- **Follow-up activity** from `activities.json` and `notes.json` — sort
  chronologically. User-authored notes live in `notes.json`; system activity in
  `activities.json`. If both are empty, say so in the report.
- Contact email or user identifier from metadata/event `user`
- Submission timestamp (`event.dateCreated`, UTC)
- Associated event ID, replay ID, trace ID, release, environment, device, OS
  from event tags/contexts
- Any linked issue or transaction

If auth fails, tell the user to run `sentry auth login` and stop.

Show the user a short header with: feedback slug, submission time (converted
to Pacific Time), reporter (email or "anonymous"), release, environment, and
the verbatim user message. Keep the message quoted, not paraphrased.

## Step 3: Pull the associated event, replay, and trace if any

Use `/tmp/sentry_feedback/event_<id>.json` from Step 2. Note especially:

- The event's exception type and top stack frame (if any).
- Breadcrumbs in the minute leading up to the feedback.
- Replay URL (don't try to render it — just include the link).
- Tags: device model, iOS version, app version, locale, network, plus the
  build's `release` and `git-commit-hash` — keep both for the correlation below.

If there is no linked event, that's fine — note it and proceed with logs only.

### Correlate the reporter's build to shipped fixes

The feedback event stamps the exact build the reporter was running: the
`release` tag (e.g. `com.artisanalsoftware.PodHaven@1.0+498`) and a
`git-commit-hash` tag (e.g. `967ddf79`). Use them — this is the only reliable
way to answer "did my fix actually reach this user?" and "is this a recurrence
of something I already fixed?".

- The build number `NNN` from the release maps to git tag `v1.0bNNN` (build
  498 → `v1.0b498`); `git rev-list -n1 v1.0bNNN` resolves that tag's commit.
- The `git-commit-hash` tag is the exact commit the build was cut from — prefer
  it over the tag when both are present (they should agree).
- To test whether a specific fix shipped in the reporter's build, use
  `git merge-base --is-ancestor <fix-commit> <build-commit>` (exit 0 = the fix
  IS in the build). Check the fix commit *and* the PR merge commit if unsure.
- Whenever the feedback resembles a known or previously-"fixed" bug, run this
  check and state the result verbatim in the report, e.g. "build 498 (commit
  967ddf79) **does** contain the #274 fix `0cc82c8c`". A failure that recurs on
  a build which already has the fix means the fix is incomplete — not that the
  reporter is on a stale build. That distinction changes the whole verdict.
- Search `memory/` and closed GitHub issues for the suspected bug first, so you
  have concrete fix commits / PR numbers to test ancestry against.

## Step 4: Hunt for related Sentry issues right before the feedback

Users typically file feedback in the moments after something went wrong, so
the most useful issue is often *not* the one Sentry auto-linked (or none was
linked). Search Sentry for issues whose events fired in the window leading up
to the feedback submission and surface them even when nothing is attached to
the feedback itself.

Convert the feedback timestamp to an ISO range (10 minutes before submission,
1 minute after), then run:

```bash
bash .agents/skills/sentry-cli/search_related_errors.sh \
  --period '2026-05-30T00:10:00Z..2026-05-30T00:21:00Z' \
  --query 'user.id:<uuid>' \
  --out /tmp/sentry_feedback_related.json
```

Use `..` between timestamps (not `/`). Widen the start time to 30 minutes before
only if the window is empty.

**Reporter scope:** if the feedback event exposes `user.id`, filter on it first.
**Fallback scope:** if no reporter identifier is available, omit `user.id` and
add `release:<release> environment:<environment>` — say explicitly in the report
that matches are release-wide, not reporter-specific.

Read `/tmp/sentry_feedback_related.json` — sort by timestamp, keep the top ~5.
For each row capture: issue short ID, title, timestamp (PT), and whether the
reporter's identifier appears on the event.

If Step 3 already pulled a linked event, this search may rediscover the same
issue group — fine, but still surface any *other* issues clustered around the
same time. Multiple distinct errors right before a feedback usually mean one
underlying failure produced several symptoms; the linked event is often just
whichever one Sentry happened to attach.

If nothing relevant turns up, say so plainly ("no Sentry issues from this
reporter in the 10 minutes before feedback") rather than omitting the section.

## Step 5: Download the reporter's NDJSON logs from the feedback event

PodHaven attaches the reporter's local NDJSON logs to every feedback event,
so the right logs to analyze are the ones on the Sentry event — **not** the
developer's iCloud Drive copies. Different device, different user, different
session.

**Mental model — who owns these files:**

- The NDJSON files are written by the app (`log.ndjson` by PodHaven, `widget-log.ndjson` by the widget extension — separate processes, separate loggers). The app attaches them at feedback-submission time.
- Sentry is purely the courier. It doesn't generate, parse, rotate, trim, or expire the logs. Whatever the app uploaded is what's there.
- Retention is entirely an app-side decision: per-launch reset vs. rolling buffer vs. size cap are all logger policies. If the window looks suspiciously short or stale, the explanation is in PodHaven's logger code, not anywhere in Sentry.
- App-log and widget-log retention differ because they're two different processes with two different loggers. Apples-to-apples "freshness" comparisons across them don't hold.
- "Missing attachments" means the *app* failed to attach (timing, disk, code path), not that Sentry lost them.
- This also bounds what fixes you can recommend: if the conclusion is "we couldn't tell because the log only goes back X seconds," the action is to change PodHaven's logger policy, not to ask Sentry for more data.

1. Read attachment names from `/tmp/sentry_feedback/attachments.json`. If the
   feedback had no linked event, fall back to the highest-ranked related event
   from Step 4 — download attachments for that event instead.
2. Expect at minimum two attachments named:
   - `log.ndjson` — the app log
   - `widget-log.ndjson` — the widget log
   If other `.ndjson` files appear, download them too and mention them. If a
   name diverges from the expected pair, note it and proceed with what you got.
3. Create a per-feedback working directory and download attachments:

```bash
bash .agents/skills/sentry-cli/download_event_attachments.sh \
  --event <event_id> \
  --dir ~/Library/Caches/analyze-sentry-feedback/<feedback-slug>/
```

Replace `:` in the slug with `-` for a path-safe directory name (e.g.
`podhaven-7485822944`). Preserve original filenames (`log.ndjson`,
`widget-log.ndjson`).
4. Sanity-check the downloads: each file should be non-empty NDJSON, and the
   latest entry should be near (within seconds to a few minutes of) the
   feedback timestamp. If a file is empty, truncated, or its latest entry is
   hours away from the feedback timestamp, call that out — it changes how
   much weight the timeline deserves.

Fallbacks, in order, if the attachment route fails:

- If the event has zero attachments: say so plainly in the report. Do **not**
  silently substitute the developer's iCloud Drive logs unless the reporter
  is provably the developer themselves (e.g. matching `user.id` and a build
  hash consistent with the local install). When in doubt, skip the fallback
  and report "no logs available — feedback had no event attachments".
- If the user provides explicit log paths in the same turn, prefer those over
  both the attachments and any fallback.
- The legacy local paths, used only when the fallback condition above holds:
  - `/Users/jubi/Library/Mobile Documents/com~apple~CloudDocs/Podhaven Assets/log.ndjson`
  - `/Users/jubi/Library/Mobile Documents/com~apple~CloudDocs/Podhaven Assets/widget-log.ndjson`

## Step 6: Analyze the logs with the `analyze-logs` script

**Do not hand-roll log parsing.** Analyze the **downloaded** NDJSON from Step 5
with the `analyze-logs` skill's bundled script — `scripts/log_summary.py` in
that skill's directory. Invoke the `analyze-logs` skill to load its full
reference (every flag, the format spec). Ad-hoc `python`/`jq` only earns its
place for a custom aggregation the script genuinely cannot express, and only
*after* the script's orient pass — never as the first move.

The reporter's `log.ndjson` is a rolling buffer that usually spans many app
launches; the feedback is almost always about the *last* one. Work it in this
order:

1. **Sessionize.** `log_summary.py <log> --sessions` lists the app launches.
   Pick the session whose time range contains the feedback timestamp.
2. **Scope to that session.** Pass `--session N` on every later command so the
   analysis covers the incident launch, not hours of unrelated history.
3. **Find storms/loops.** `--session N --call-sites` surfaces the chattiest
   `file:line` even when every line is `debug`/`notice` and nothing crosses
   `warning` — runaway loops never alert, so the level filters won't catch them.
4. **Timeline.** Pass the Sentry timestamp directly to `--around` — it accepts
   ISO-8601 with timezone (e.g. `2026-06-12T16:26:55Z`) as well as epoch ms;
   never hand-convert to epoch. Use a window wide enough for lead-up *and*
   aftermath: start `--window-ms 60000`, widen to `300000` then `1800000` if
   empty. Add `--oneline` for a dense one-entry-per-line timeline. Run
   `--min-level warning` first, then without the level filter if nothing
   surfaces.

Run the same scoped analysis on `widget-log.ndjson` whenever the feedback
plausibly involves widget behavior — i.e. the user mentions home/lock screen,
widget, "Up Next", artwork, "won't update", or the app log shows widget-related
subsystems firing near the feedback time. When in doubt, check it; pulling an
empty widget window is cheap.

If the feedback comment names a specific feature (search, downloads, playback,
sync, etc.), also re-run filtered by the corresponding
`--subsystem`/`--category`/`--file` once you've eyeballed the time-window output.

### Symbolicate MetricKit diagnostics if present

If the scoped timeline includes a `MetricKit <category> diagnostic received`
entry (subsystem `PodHaven`, category `MetricKit`, with a
`metricKitDiagnostic` metadata blob), the raw frames are useless as-is —
each carries only `binaryUUID + offsetIntoBinaryTextSegment`. Run
`analyze-logs/scripts/symbolicate_metrickit.py` against the same downloaded
NDJSON file to resolve them:

```bash
python3 .agents/skills/analyze-logs/scripts/symbolicate_metrickit.py \
  "$LOG_PATH" --category crash
```

Lead with `--category <category>` over the whole file, not `--around` the
feedback timestamp: MetricKit delivers diagnostics at the *next launch* after
the incident, so the entry's timestamp rarely matches the crash or the
feedback. Narrow with `--around <sentry-timestamp>` (ISO-8601 with timezone
accepted, same as `log_summary.py`) only when the file holds many diagnostics
of that category; if the window comes back empty, the script lists the
matching entries outside it.

The script fetches the matching dSYM from Sentry's Debug Files API (Sentry
keys them by debug-id == binary UUID), caches it under
`~/Library/Caches/podhaven-symbolicate`, and runs `atos`. Quote the resolved
top frames in the Timeline section instead of the raw `Binary+offset` line —
they are usually the most important evidence in the report.

## Step 7: Synthesize

Build one report. Lead with the user's words, then the evidence, then the
verdict and suggested fix. The reader should be able to act on this without
opening Sentry themselves.

When forming the inferred root cause, weight signals in this rough order:

1. **Triage notes from this invocation** — the user just told you what to focus
   on; respect that unless the logs flatly contradict it.
2. **Sentry follow-ups** — later comments often reflect what the user has
   already learned or ruled out since submission. A follow-up that says "turned
   out to be X" beats anything the original message implied.
3. **Linked event / stack frame / breadcrumbs** — concrete crash or error data.
4. **Related Sentry issues from Step 4** — same-user errors in the minutes
   before submission are usually the trigger, especially when no event was
   directly linked to the feedback. Treat them as peers to the linked event;
   prefer same-user matches over release-wide ones.
5. **Reporter's attached NDJSON log timeline** — broadest context, but also
   the noisiest.
6. **Original feedback text** — frames the user's experience but is often
   imprecise about cause.

If two sources disagree, name the disagreement in *Alternatives considered*
rather than silently picking one.

Report format:

```
# Sentry Feedback — <slug>

## Reporter
- **Submitted:** <PT timestamp>  (<UTC timestamp>)
- **From:** <email or "anonymous">
- **Release / env:** <release> / <environment>
- **Build vs. known fixes:** <build number + git-commit-hash, and which
  relevant fixes it does/does not contain per Step 3; omit if not a suspected
  recurrence of a known bug>
- **Device:** <model, OS version> (if known)
- **Replay:** <link or "none">
- **Event:** <event id and short type, or "none linked">

## What the user said
> <verbatim feedback message>

## Sentry follow-ups
(Chronological list of every comment/note/activity entry added on the Sentry
feedback after submission. Format each as `<PT timestamp> — <author>: <verbatim
text>`. If none exist, write "None." If notes/activities files were empty after
fetch, write "None fetched."

## Related Sentry issues near feedback time
(Issues from Step 4 whose events fired in the window leading up to the
feedback. Format each line as `<PT timestamp> — <issue short id> — <title>
(<error type>, <N events>, <same-user|release-wide>)`. List most recent first.
Note the search window used (e.g. "10 min before, 1 min after"). If none, write
"None found in <window>".)

## Triage notes from this invocation
(Any free-text the user attached alongside the URL when they ran the skill,
quoted verbatim. Omit the section if there were none.)

## Timeline (PT)
- <hh:mm:ss.mmm>  <subsystem>/<category>  <level>  <one-line message>
- ...

(Five to fifteen lines from the app log, plus widget lines if relevant, in
chronological order. Mark widget lines as `[widget]`. Quote enough to support
the conclusion, no more.)

## Findings
- **Direct observations:** what the logs actually show.
- **Inferred root cause:** the most likely explanation, with confidence
  (high/medium/low) and what would raise confidence.
- **Alternatives considered:** other plausible causes you ruled out and why.

## Suggested fix
Prose only — name the suspect file(s) and function(s), describe the change,
and call out any tests that should accompany it. Do not edit code in this
skill. If the fix is non-obvious or the root cause is uncertain, recommend
the next investigative step instead (e.g. "add logging at X", "reproduce by Y").

## Open questions
Anything the user could clarify that would sharpen the diagnosis (e.g.
"was this on cellular?", "do you remember which screen you were on?").
Omit this section if there are no useful follow-ups.
```

## Rules

- Convert all user-facing timestamps to Pacific Time and include the timezone.
- Quote the user's feedback verbatim. Do not paraphrase or "clean it up".
- Never edit application code from inside this skill — the output is analysis
  and a fix recommendation, not a patch. If the user wants the fix shipped,
  they can follow up with `/issuefix` or ask explicitly.
- Do not invent log lines, event IDs, or stack frames. If a piece of data is
  missing, say "not available" rather than guessing.
- If the feedback has no linked event and the logs show nothing notable in
  the surrounding 30 minutes, say so plainly and list the open questions —
  don't pad the report with unrelated warnings.
- Keep the report dense. Every line should help the reader either understand
  what happened or decide what to do next.
- When the feedback looks like a known or already-"fixed" bug, correlate the
  reporter's build/commit to git ancestry (Step 3) before concluding. A
  recurrence on a build that already contains the fix is an incomplete fix —
  the report must say so explicitly rather than blaming a stale build.
