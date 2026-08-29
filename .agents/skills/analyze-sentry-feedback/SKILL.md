---
name: analyze-sentry-feedback
description: >-
  Triage a Sentry user feedback item end to end: fetch the feedback, download
  the reporter's NDJSON logs (app and widget) that PodHaven attaches to the
  feedback event, correlate them to the report time, and explain what likely
  happened plus a suggested fix, then funnel sanitized findings into a GitHub
  issue that tracks the feedback through closeout. Use when the user pastes a
  Sentry feedback URL (e.g.
  .../issues/feedback/?feedbackSlug=podhaven:NNN...), references a feedback by
  slug or ID, or asks to investigate a piece of user feedback from Sentry.
  Invoked with no reference at all, it lists the feedback entries still
  unresolved in Sentry and lets the user pick one to triage.
user_invocable: true
disable-model-invocation: true
argument: >-
  A Sentry feedback URL, a feedbackSlug like `podhaven:7485822944`, or a bare
  numeric feedback ID. Any additional free-text the user types alongside that
  reference (hunches, context, focus areas, "ignore X", "this user is on beta",
  etc.) should be treated as triage instructions and surfaced in the report.
  If no reference is provided, list the feedback entries still unresolved in
  Sentry and let the user choose one (Step 0).
---

# Analyze Sentry Feedback

Triage a single Sentry user feedback report by combining the Sentry side (the
feedback text, contact info, replay/event/trace links, timestamp) with the
NDJSON logs the iOS app and widget attach directly to the feedback event in
Sentry. Those attachments are the *reporter's* logs and the only logs that
correctly correspond to the report — not the developer's local iCloud Drive
copies.

The goal is one focused private report plus one deduplicated GitHub issue: what
the user experienced, what the logs around that time show, the most likely root
cause, how to fix or investigate it, and the originating feedback slug to
resolve when that issue is eventually closed. Sentry remains the source of
private reporter details; GitHub becomes the durable work tracker.

## Scope

One feedback and one tracking issue at a time. Do **not** use this skill to
summarize many feedbacks at once or to do general Sentry log triage — for that,
use `analyze-sentry-logs`. For a non-feedback error issue (an `issues/<id>` URL
or short ID), use `analyze-sentry-issue`. The no-argument listing in Step 0 is
the one exception: it only enumerates open entries so the user can pick one to
triage.

This workflow must not dirty the repository. Reporter attachments belong in
the cache directory from Step 6, fetched bundles belong under `/tmp`, and the
GitHub issue is the only durable record this skill creates or updates.

## `issuefix` prerequisite contract

This project-scoped skill may serve as an `issuefix` intake prerequisite when
an issue body or comment contains the exact marker
`<!-- issuefix-prerequisite: analyze-sentry-feedback podhaven:<numeric-id> -->`.
The only additional trusted marker author is `github-actions[bot]`, the login
used by the checked-in daily checker. Do not trust markers from other logins
unless this project contract is deliberately updated. The argument is that
`podhaven:<numeric-id>` slug. A complete block from
`<!-- analyze-sentry-feedback-findings:start -->` through
`<!-- analyze-sentry-feedback-findings:end -->` in the same issue body is the
completion signal. When invoked this way, run this entire triage workflow,
enrich the issue without changing the worktree, then return control to
`issuefix`; do not implement the proposed fix here.

## Step 0: No reference given? List unresolved feedback

When invoked with no feedback URL, slug, or ID (and none is obvious from the
conversation), switch to discovery mode instead of asking for a reference:

1. List the feedback issues still unresolved in Sentry (auth prerequisites as
   in Step 3):

```bash
sentry issue list artisanal-software/podhaven \
  --query 'issue.category:feedback is:unresolved' \
  --period 365d --limit 100 --fresh --json
```

2. From each row keep: numeric `id`, `shortId`, `metadata.message`,
   `metadata.contact_email`, and `permalink` (its `feedbackSlug=` query param
   is the slug). Feedback rows carry no timestamps in this listing; higher
   numeric IDs are newer.
3. Fetch GitHub issues in `jubishop/podhaven` once, including closed issues.
   Match each feedback by the exact `<!-- sentry-feedback:<slug> -->` body
   marker used by `bin/check-sentry-feedback`, with the Sentry permalink as a
   fallback. The managed findings marker from Step 9 distinguishes analyzed
   issues from intake placeholders.
4. Present the entries newest first and let the user choose one (multiple-
   choice prompt if supported, otherwise a numbered list), one line each:
   `PODHAVEN-XX  podhaven:<id> — "<message, trimmed to one line>"
   (<contact email or anonymous>; GitHub: #N intake|#N analyzed|#N
   closed|untracked)`.
5. If there are no unresolved entries, say so plainly and stop.
6. When the user picks one, continue to Step 1 with `podhaven:<id>` as the
   reference, treating anything else they typed alongside the pick as triage
   notes.

## Step 1: Parse the reference and the user's own notes

From the argument, extract:

1. **Feedback slug**: prefer the value of `feedbackSlug=` in the URL (URL-decode
   it). If only a numeric ID is provided, assume the slug is `podhaven:<id>`.
2. **Numeric feedback ID**: the part after `:` in the slug.
3. **Path-safe slug**: the slug with `:` replaced by `-` (e.g.
   `podhaven-7485822944`) — names the attachment download directory (Step 6).
4. **Sentry org**: `artisanal-software` (default for this repo).
5. **Project ID**: `4508469264711681` if present in the URL, else assume the
   PodHaven project.
6. **User notes alongside the link**: any free-text the user typed in the same
   argument that isn't part of the URL/slug. Treat it as triage instructions
   (e.g. "I think this is the search bug from last week", "ignore the widget
   side", "user is on TestFlight build 412"). Carry these notes forward — they
   shape what to focus on in Steps 5–7 and must appear verbatim in the report.

Tell the user the parsed slug in one short line before fetching, so they can
catch a mis-paste early. If the user attached notes, echo them back in the
same line so they know they were picked up (not silently dropped).

Capture `git status --short` before continuing. Compare it again before the
final response; the output must be identical because this workflow never owns
repository changes.

## Step 2: Find the tracking issue and prior analysis

Search all GitHub issues in `jubishop/podhaven`, open and closed, for the exact
`<!-- sentry-feedback:<slug> -->` body marker. Fall back to an exact match on
the Sentry permalink. Read the matching issue body and comments before fetching
anything else.

- The daily `bin/check-sentry-feedback` workflow may already have created a
  placeholder issue. Its generic title and instruction comment offer two
  equivalent entry paths: direct analysis through `bin/sfeedback`, or analysis
  as a prerequisite when the issue is passed to `issuefix`. Neither path counts
  as complete until this skill adds the managed findings block.
- A complete managed findings block means the issue was already analyzed.
  Summarize its findings, fixes, PR links, or disposition to the user and carry
  them into Step 8 as the comparison baseline. Do not presume that another run
  requires another GitHub write.
- Do not redo settled analysis unless the user asks or current Sentry evidence
  materially differs. Say exactly what changed when it does.
- If multiple issues match, prefer the exact-marker issue, report the
  duplicates, and update only the canonical issue in Step 9.
- If no issue matches, remember that one must be created in Step 9.
- A legacy `memory/sentry_feedback/<path-safe-slug>.md` file may be read as
  historical evidence when it exists, but never create, edit, or delete one.
  GitHub is the canonical record for all new analysis.

Keep the canonical issue number, URL, title, body, state, and Sentry permalink
for Step 9. Do not modify it until the evidence has been synthesized.

## Step 3: Fetch the feedback from Sentry

Requires the **`sentry` CLI** and auth (`sentry auth login`). If the command is
missing, report that prerequisite and stop. Do not use the Sentry MCP server.

Run:

```bash
bash .agents/scripts/sentry-cli/fetch_feedback_bundle.sh <slug> \
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

## Step 4: Pull the associated event, replay, and trace if any

Use `/tmp/sentry_feedback/event_<id>.json` from Step 3. Note especially:

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

## Step 5: Hunt for related Sentry issues right before the feedback

Users typically file feedback in the moments after something went wrong, so
the most useful issue is often *not* the one Sentry auto-linked (or none was
linked). Search Sentry for issues whose events fired in the window leading up
to the feedback submission and surface them even when nothing is attached to
the feedback itself.

Convert the feedback timestamp to an ISO range (10 minutes before submission,
1 minute after), then run:

```bash
bash .agents/scripts/sentry-cli/search_related_errors.sh \
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

If Step 4 already pulled a linked event, this search may rediscover the same
issue group — fine, but still surface any *other* issues clustered around the
same time. Multiple distinct errors right before a feedback usually mean one
underlying failure produced several symptoms; the linked event is often just
whichever one Sentry happened to attach.

If nothing relevant turns up, say so plainly ("no Sentry issues from this
reporter in the 10 minutes before feedback") rather than omitting the section.

## Step 6: Download the reporter's NDJSON logs from the feedback event

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
   from Step 5 — download attachments for that event instead.
2. Expect at minimum two attachments named:
   - `log.ndjson` — the app log
   - `widget-log.ndjson` — the widget log
   If other `.ndjson` files appear, download them too and mention them. If a
   name diverges from the expected pair, note it and proceed with what you got.
3. Create a per-feedback working directory and download attachments:

```bash
bash .agents/scripts/sentry-cli/download_event_attachments.sh \
  --event <event_id> \
  --issue-json /tmp/sentry_feedback/issue.json \
  --dir ~/Library/Caches/analyze-sentry-feedback/<feedback-slug>/ \
  --all
```

The directory name is the path-safe slug from Step 1. Preserve original
filenames (`log.ndjson`, `widget-log.ndjson`).
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

## Step 7: Analyze the logs with the bundled summary script

**Do not hand-roll log parsing.** Analyze the **downloaded** NDJSON from Step 6
with `.agents/skills/analyze-logs/scripts/log_summary.py`. This step contains
the incident-specific workflow and flags needed here; do not load the full
`analyze-logs` skill on top of it. Read
`.agents/skills/analyze-logs/references/podhaven-log-format.md` only when exact
field, truncation, or MetricKit payload details are necessary. Ad-hoc
`python`/`jq` only earns its place for a custom aggregation the script genuinely
cannot express, and only *after* the script's orient pass — never as the first
move.

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

## Step 8: Synthesize

Build one private report. Lead with the user's words, then the evidence, then
the verdict and suggested fix. The report may contain reporter details from
Sentry; the public GitHub issue created from it in Step 9 may not.

When forming the inferred root cause, weight signals in this rough order:

1. **Triage notes from this invocation** — the user just told you what to focus
   on; respect that unless the logs flatly contradict it.
2. **Prior conclusions from the tracking issue (Step 2)** — settled verdicts
   and shipped fixes from earlier work; only new evidence overturns them.
3. **Sentry follow-ups** — later comments often reflect what the user has
   already learned or ruled out since submission. A follow-up that says "turned
   out to be X" beats anything the original message implied.
4. **Linked event / stack frame / breadcrumbs** — concrete crash or error data.
5. **Related Sentry issues from Step 5** — same-user errors in the minutes
   before submission are usually the trigger, especially when no event was
   directly linked to the feedback. Treat them as peers to the linked event;
   prefer same-user matches over release-wide ones.
6. **Reporter's attached NDJSON log timeline** — broadest context, but also
   the noisiest.
7. **Original feedback text** — frames the user's experience but is often
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
  relevant fixes it does/does not contain per Step 4; omit if not a suspected
  recurrence of a known bug>
- **Device:** <model, OS version> (if known)
- **Replay:** <link or "none">
- **Event:** <event id and short type, or "none linked">

## What the user said
> <verbatim feedback message>

## Prior analysis
(Summary of earlier findings or dispositions from the tracking GitHub issue,
plus any useful read-only legacy-ledger evidence. Omit the section on
first-time triage.)

## Sentry follow-ups
(Chronological list of every comment/note/activity entry added on the Sentry
feedback after submission. Format each as `<PT timestamp> — <author>: <verbatim
text>`. If none exist, write "None." If notes/activities files were empty after
fetch, write "None fetched."

## Related Sentry issues near feedback time
(Issues from Step 5 whose events fired in the window leading up to the
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

## GitHub issue
<created|enriched|updated|reopened|reused unchanged> <issue number and URL>.
Sentry feedback `<slug>` remains unresolved and should be resolved when this
issue is closed.
```

## Step 9: Funnel the findings into GitHub

Before delivering the final report, ensure exactly one GitHub issue carries
the actionable, public-safe result of the analysis. Creating, enriching, or
materially updating this issue is automatic; do not ask for confirmation. An
already-accurate issue is a successful no-write outcome.

1. If no matching issue exists, create one in `jubishop/podhaven` with a concise
   action-oriented title. Use `Investigate ...` when the cause is uncertain.
2. If the canonical issue is an intake placeholder, enrich it by editing its
   title and body directly. Do not post the findings as another comment.
   Preserve a meaningful human-written title and leave the checker's
   `sfeedback` / `issuefix` prerequisite comment alone as history. Adding the
   managed findings block satisfies that prerequisite for either entry path.
3. If the issue already has a complete managed findings block, compare the new
   synthesis to it. Update the title or managed block only for a material
   change, such as a new Sentry follow-up or user-provided context that changes
   the conclusion, a corrected root cause or confidence level, or a changed
   proposed resolution or verification plan. Rewording, formatting cleanup, a
   rerun timestamp, or repeated evidence is not material.
4. If nothing material changed, make **no GitHub writes**: do not edit the
   title, body, state, or comments. Report the outcome as `reused unchanged`.
5. If a matching issue is closed but the current synthesis shows work remains,
   reopen it rather than creating a duplicate. If its prior disposition still
   holds and the managed findings remain accurate, leave it closed and reuse it
   unchanged.
6. Keep the exact marker `<!-- sentry-feedback:<slug> -->` in the body so
   `bin/check-sentry-feedback` and later runs deduplicate it.
7. When creating, enriching, or materially updating, add or replace only the
   section between
   `<!-- analyze-sentry-feedback-findings:start -->` and
   `<!-- analyze-sentry-feedback-findings:end -->`. Preserve every human-written
   line outside that managed block. Keep any temporary issue-body file under
   `/tmp`, never in the repository. Use this body shape:

```markdown
<!-- sentry-feedback:<slug> -->
This issue tracks [Sentry feedback `<slug>`](<permalink>) (`<shortId>`).
Keep the feedback unresolved in Sentry while this issue remains open.

<!-- analyze-sentry-feedback-findings:start -->
## Findings

- **User-visible symptom:** <sanitized paraphrase>
- **Root cause:** <conclusion and confidence>
- **Evidence:** <minimal technical evidence needed to act>
- **Unknowns:** <material gaps, or "None">

## Proposed resolution

<files/functions or investigative boundary, proposed behavior, and why>

## Verification

- <regression proof or investigative checks>

## Sentry closeout

When this GitHub issue is ready to close, also resolve Sentry feedback
`<slug>`. Reporter text and identity remain in Sentry and must not be copied
into this public issue.
<!-- analyze-sentry-feedback-findings:end -->
```

The GitHub findings must be sufficient for the `issuefix` skill or another
issue-based workflow to start without repeating the triage. Include relevant
public file, function, issue, PR, and commit references. Do not include the
reporter's verbatim text, email, user ID, replay/event/trace identifiers, raw
log lines, or other private/device-specific data. Summarize only the technical
evidence needed to act and link to Sentry for the protected context.

Leave the feedback unresolved during ordinary triage. The issue's closeout
section is the handoff for resolving it after the fix or disposition is
complete. If the user explicitly directs immediate resolution because no work
remains, honor that only after the issue records the disposition.

If GitHub authentication or issue creation/update fails, deliver the report
and the exact blocker, but do not create a local ledger or any other fallback
file. Tell the user to authenticate with `gh auth login` when that is the
failure. Otherwise, finish by giving the issue number and URL, whether it was
created, enriched, materially updated, reopened, or reused unchanged, and that
repository status is unchanged from the baseline captured in Step 1.

## Rules

- Convert all user-facing timestamps to Pacific Time and include the timezone.
- Quote the user's feedback verbatim in the private report. Never copy it or
  reporter-identifying details into the public GitHub issue.
- Never edit repository files from inside this skill, including application
  code, docs, and `memory/sentry_feedback/`. Do not commit or push. Temporary
  bundles under `/tmp` and reporter attachments under the user cache are fine.
  The output is analysis plus a GitHub issue ready for `issuefix` or another
  issue-based workflow.
- Do not invent log lines, event IDs, or stack frames. If a piece of data is
  missing, say "not available" rather than guessing.
- If the feedback has no linked event and the logs show nothing notable in
  the surrounding 30 minutes, say so plainly and list the open questions —
  don't pad the report with unrelated warnings.
- Keep the report dense. Every line should help the reader either understand
  what happened or decide what to do next.
- When the feedback looks like a known or already-"fixed" bug, correlate the
  reporter's build/commit to git ancestry (Step 4) before concluding. A
  recurrence on a build that already contains the fix is an incomplete fix —
  the report must say so explicitly rather than blaming a stale build.
- Never end a successful triage without creating, enriching, materially
  updating, reopening, or explicitly reusing its canonical GitHub issue
  unchanged (Step 9). Never use a repo file as a fallback when an external
  write is blocked.
