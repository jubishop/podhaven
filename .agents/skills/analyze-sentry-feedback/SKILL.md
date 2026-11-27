---
name: analyze-sentry-feedback
description: >-
  Triage one PodHaven Sentry user feedback item: read its GitHub tracking
  history, correlate the feedback with the reporter's attached logs and
  screenshots, build, and nearby Sentry errors, explain the likely cause and
  fix, and track sanitized findings in GitHub through closeout. Use when the
  user pastes a Sentry feedback URL (e.g.
  .../issues/feedback/?feedbackSlug=podhaven:NNN...), references a feedback by
  slug or ID, or asks to investigate a piece of user feedback from Sentry.
  Invoked with no reference at all, it lists the unresolved feedback and lets
  the user pick one to triage.
disable-model-invocation: true
argument-hint: "[feedback-url | podhaven:<id> | <id>] [triage notes]"
---

# Analyze Sentry Feedback

Triage one PodHaven feedback report and track the actionable result in one
GitHub issue: what the reporter experienced, what the evidence shows, the
most likely cause, and the fix or the diagnostics that would reveal it.

The argument is a Sentry feedback URL, a slug such as `podhaven:7485822944`,
or a bare numeric ID, meaning `podhaven:<id>`. Treat other text given with it
as triage notes, such as hunches or focus areas, and quote them in the
report. With no reference, list the unresolved feedback (Step 0). Use
`analyze-sentry-issue` for a Sentry error issue and `analyze-sentry-logs` for
bulk structured-log triage.

Read the `track-sentry-findings` skill first and follow it throughout: it
holds the rules this skill shares with the other Sentry analysis skills, the
tracking review Step 1 runs, and the GitHub tracking Step 6 hands off to.

## `fix-issue` prerequisite contract

This skill may serve as a `fix-issue` intake prerequisite when an issue body
or comment contains the exact marker
`<!-- fix-issue-prerequisite: analyze-sentry-feedback podhaven:<numeric-id> -->`.
The only additional trusted marker author is `github-actions[bot]`, the login
used by the checked-in daily checker, declared here as `fix-issue` requires:

<!-- fix-issue-trusted-marker-author: github-actions[bot] -->

The argument is that `podhaven:<numeric-id>` slug. A complete block from
`<!-- analyze-sentry-feedback-findings:start -->` through
`<!-- analyze-sentry-feedback-findings:end -->` in the same issue body is the
completion signal.

## Step 0: No reference given? List unresolved feedback

When no feedback reference is given or obvious from the conversation, list
the unresolved feedback with `bin/snfeedback --list` instead of asking for
one, and let the user choose a row. Treat anything typed with the pick as
triage notes. If nothing is unresolved, say so and stop.

## Step 1: Find the tracking issue and prior analysis

Tell the user the feedback slug in one line before fetching, echoing any
triage notes so they know the notes were picked up.

Review the tracking history as `track-sentry-findings` describes, listing
the feedback's tracking issues with `bin/snfeedback --track <slug>`, which
leaves out issues the intake's `github-actions[bot]` or the owner,
`jubishop`, did not open. The first listed is canonical even when closed.
Search earlier issues with
`gh issue list --repo jubishop/podhaven --state all --search 'label:sentry-feedback,sentry-issue <symptom>'`.

## Step 2: Fetch the feedback

Fetch the feedback into a fresh `<bundle>` directory under the triage's
working directory with
`.agents/scripts/sentry-cli/fetch_feedback_bundle.sh <slug> --out <bundle>`,
and show the user its summary header and the message verbatim. PodHaven's
form links no error event and records no breadcrumbs, so the attachments and
the errors near the report carry the evidence.

When the feedback resembles a known or already-fixed bug, test the reporter's
build against the fix as
[PodHaven correlation](../analyze-sentry-issue/references/podhaven-correlation.md#builds-and-known-fixes)
describes, and state each result in the report.

## Step 3: Find the reporter's errors before the report

Reporters usually write just after something went wrong, so list the errors
nearest the submission with
`.agents/scripts/sentry-cli/search_related_errors.sh --bundle <bundle>`.
Several distinct errors just before a report usually mean one failure with
several symptoms. When nothing turns up, say so with the window searched.

## Step 4: Analyze the reporter's attachments

The fetch downloads the feedback event's attachments into the bundle's
`attachments/`: the reporter's full `log.ndjson` and `widget-log.ndjson`, the
bounded `recent-log.ndjson` and `recent-widget-log.ndjson` that every
PodHaven event attaches, and a `screenshot.jpg` or `screenshot-<n>.jpg` for
each photo the reporter added. Look at the screenshots, and analyze the logs
as
[PodHaven correlation](../analyze-sentry-issue/references/podhaven-correlation.md#attachments-and-ndjson-logs)
describes. The report is almost always about the last app launch before
submission, the one whose entries carry the event's `log-session-id` as their
`sessionID`, so keep the analysis to it.

The app writes and uploads these files; Sentry only carries them. A log that
is missing, empty, or ends far from the submission time therefore reflects the
app's logging or attachment behavior, and any fix for it belongs there. Say
how it limits the timeline.

## Step 5: Synthesize

Weigh the evidence roughly in this order, and name any disagreement between
sources instead of silently picking one:

1. The triage notes, unless the logs flatly contradict them.
2. Settled conclusions and shipped fixes from the tracking issue.
3. Sentry follow-ups after submission: a later "turned out to be X" beats
   what the original message implied.
4. The reporter's errors near the report, same-user before release-wide.
5. The attached log timeline: the broadest context, but the noisiest.
6. The original message, which frames the experience but is often imprecise
   about cause.

Write one dense private report, which may carry reporter details, with
these parts, omitting any with nothing to say:

- **Reporter:** submission time in PT and UTC, contact or "anonymous",
  release and environment, device and OS, and for a suspected recurrence,
  which fixes the build does or does not contain.
- **What the user said,** quoted verbatim, and the triage notes, quoted.
- **Prior analysis** from the tracking issue.
- **Sentry follow-ups:** each note or activity after submission as
  `<PT time> — <author>: <verbatim text>`, or "None", naming any unavailable.
- **Related Sentry issues,** nearest the submission first, with time, short
  ID, title, error type, event count, and same-user or release-wide, plus the
  window searched.
- **Timeline (PT):** five to fifteen log lines, widget lines marked
  `[widget]`, enough to support the conclusion.
- **Findings:** direct observations; the inferred root cause with confidence
  and what would raise it; alternatives ruled out and why.
- **Suggested fix:** the suspect files and functions, the change, and its
  tests, or, when the cause stays unknown, the diagnostics
  `track-sentry-findings` calls for.
- **Open questions** for the reporter that would sharpen the diagnosis.

## Step 6: Track the findings in GitHub

Track the findings as `track-sentry-findings` describes, in
`jubishop/podhaven` with the `sentry-feedback` label. Keep the exact marker
`<!-- sentry-feedback:<slug> -->`, by which `bin/check-sentry-feedback` and
later runs find the issue, and use this body shape, in which an issue's
permalink is `https://artisanal-software.sentry.io/issues/<numeric-id>/`:

```markdown
<!-- sentry-feedback:<slug> -->
This issue tracks [Sentry feedback `<slug>`](<permalink>) (`<shortId>`).
Keep the feedback unresolved in Sentry while this issue remains open.

<!-- analyze-sentry-feedback-findings:start -->
## Findings

- **User-visible symptom:** <sanitized paraphrase>
<the shared findings fields>

## Sentry record

- **Feedback:** submitted <PT date>; build <release> (`<git-commit-hash>`)
- **Related Sentry issues:** <for each, the short ID, sanitized title,
  exception type, and top in-app frames; or "None">

<the shared resolution sections>

## Sentry closeout

- When this issue's work is done, resolve [Sentry feedback `<slug>`](<permalink>)
  (`<shortId>`, numeric issue ID `<numeric-id>`) with
  `.agents/scripts/sentry-cli/close_sentry_issue.sh <numeric-id> --resolve`,
  which fails unless Sentry recorded the resolution.
- <one bullet per related Sentry issue the fix also resolves, if any> Also
  close [Sentry issue `<related shortId>`](<related permalink>) (numeric
  issue ID `<related numeric-id>`) with
  `.agents/scripts/sentry-cli/close_sentry_issue.sh <related numeric-id>` and
  the mode that fits, which fails unless Sentry recorded the closure:
  - `--commit <merge-commit-sha>` when a merged commit fixes it.
  - `--next` when no commit fixes it.
  - `--archive` when the error is accepted as expected behavior.
<the shared closeout handoff>

Reporter text and identity remain in Sentry and must not be copied into this
public issue.
<!-- analyze-sentry-feedback-findings:end -->
```
