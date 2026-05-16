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

## When to use

- The user pastes a URL that contains `issues/feedback/` and/or `feedbackSlug=`.
- The user says "look at this feedback", "triage feedback NNN", or "what
  happened to the user who reported X".
- The user gives a slug like `podhaven:7485822944` or a bare numeric feedback
  ID and asks for analysis.

Do **not** use this skill to summarize many feedbacks at once or to do general
Sentry log triage — for that, use `analyze-sentry-logs`.

## Inputs you may receive

- A full Sentry URL, e.g.
  `https://artisanal-software.sentry.io/issues/feedback/?feedbackSlug=podhaven%3A7485822944&project=4508469264711681&...`
- A feedback slug like `podhaven:7485822944` (the part after `feedbackSlug=`,
  URL-decoded — `%3A` decodes to `:`).
- A bare numeric ID like `7485822944`. Combine with the project short name
  `podhaven` to form the slug.

If none is provided, ask the user for one before proceeding.

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

Use the available Sentry integration (the Sentry MCP server if connected,
otherwise the `sentry-cli` or Sentry REST API with the token in
`~/.sentryclirc`) to retrieve the feedback by slug. You want:

- The user's original free-text message / comment.
- **Any follow-up activity on the feedback**: notes, comments, replies, status
  changes, or assignments the project owner (the user of this skill) has added
  inside Sentry after the initial submission. These are often the most current
  context — pull them all and sort chronologically. If the Sentry integration
  exposes a separate "activity" or "notes" or "comments" endpoint for a
  feedback issue, hit it explicitly; don't assume the feedback object alone
  contains the thread.
- Contact email or user identifier, if present.
- The feedback's submission timestamp (UTC).
- The associated event ID, replay ID, trace ID, release, environment, device,
  OS version — whatever Sentry exposes for that feedback.
- Any linked issue or transaction.

If the integration only returns the base feedback and you can't find a
comments/activity endpoint, say so in the report ("no Sentry-side follow-ups
fetched — endpoint not available") rather than silently omitting that section.

If the Sentry integration is not available, tell the user what to install or
authenticate (e.g. "run `! sentry-cli login`" or "add the Sentry MCP server")
and stop.

Show the user a short header with: feedback slug, submission time (converted
to Pacific Time), reporter (email or "anonymous"), release, environment, and
the verbatim user message. Keep the message quoted, not paraphrased.

## Step 3: Pull the associated event, replay, and trace if any

If the feedback links an event ID, replay ID, or trace ID, fetch each through
the same Sentry integration. Note especially:

- The event's exception type and top stack frame (if any).
- Breadcrumbs in the minute leading up to the feedback.
- Replay URL (don't try to render it — just include the link).
- Tags: device model, iOS version, app version, locale, network.

If there is no linked event, that's fine — note it and proceed with logs only.

## Step 4: Download the reporter's NDJSON logs from the feedback event

PodHaven attaches the reporter's local NDJSON logs to every feedback event,
so the right logs to analyze are the ones on the Sentry event — **not** the
developer's iCloud Drive copies. Different device, different user, different
session.

1. List attachments on the feedback's event using the Sentry MCP:
   `get_event_attachment(organizationSlug='artisanal-software',
   projectSlug='podhaven', eventId='<feedback event id from Step 2>')`
2. Expect at minimum two attachments named:
   - `log.ndjson` — the app log
   - `widget-log.ndjson` — the widget log
   If other `.ndjson` files appear, download them too and mention them. If a
   name diverges from the expected pair, note it and proceed with what you got.
3. Create a per-feedback working directory and download each attachment by ID
   into it, preserving the original filename:
   `~/Library/Caches/analyze-sentry-feedback/<feedback-slug>/`
   (replace `:` in the slug with `-` so it's path-safe, e.g.
   `podhaven-7485822944`). Create the directory if it doesn't exist.
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

## Step 5: Analyze logs around the feedback time

Invoke the `analyze-logs` skill against the **downloaded** log paths from
Step 4, scoped to the feedback's timestamp. Convert the Sentry timestamp to
epoch milliseconds and use `--around` with a window wide enough to catch
lead-up *and* aftermath:

- Start at `--window-ms 60000` (one minute on either side).
- If that window is empty or has no errors/warnings, widen to `--window-ms 300000`
  (five minutes), then `--window-ms 1800000` (thirty minutes).
- Always run with `--min-level warning` first, then re-run without the level
  filter if nothing surfaces.

Run the same scoped analysis on `widget-log.ndjson` whenever the feedback
plausibly involves widget behavior — i.e. the user mentions home/lock screen,
widget, "Up Next", artwork, "won't update", or the app log shows widget-related
subsystems firing near the feedback time. When in doubt, check it; pulling an
empty widget window is cheap.

If the feedback comment names a specific feature (search, downloads, playback,
sync, etc.), also re-run `analyze-logs` filtered by the corresponding
subsystem/category/source-file once you've eyeballed the time-window output.

## Step 6: Synthesize

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
4. **Reporter's attached NDJSON log timeline** — broadest context, but also
   the noisiest.
5. **Original feedback text** — frames the user's experience but is often
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
- **Device:** <model, OS version> (if known)
- **Replay:** <link or "none">
- **Event:** <event id and short type, or "none linked">

## What the user said
> <verbatim feedback message>

## Sentry follow-ups
(Chronological list of every comment/note/activity entry added on the Sentry
feedback after submission. Format each as `<PT timestamp> — <author>: <verbatim
text>`. If none exist, write "None." If the integration couldn't fetch the
thread, write "Not fetched — <reason>".)

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
