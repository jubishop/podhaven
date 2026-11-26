---
name: analyze-sentry-issue
description: >-
  Diagnose one PodHaven Sentry error issue by reading its GitHub tracking
  history, then correlating representative events, impact patterns, relevant
  logs or traces, and the codebase, and track sanitized findings in GitHub
  through closeout. Use when the user provides a Sentry issue URL or ID, or
  asks what caused a PodHaven Sentry error and how to address it. Invoked
  with no reference at all, it lists the unresolved Sentry issues and lets
  the user pick one to triage.
disable-model-invocation: false
argument-hint: "[issue-url | PODHAVEN-<id> | <numeric-id>] [triage notes]"
---

# Analyze Sentry Issue

Diagnose one PodHaven error issue and track the actionable result in one
GitHub issue: what failed, who it affects, the most likely cause, and the best
fix or mitigation. Do not implement the fix here.

The argument is a Sentry issue URL, a short ID such as `PODHAVEN-42`, or a
numeric issue ID. Treat other text given with it as triage notes: scope,
constraints, or hypotheses to test, not evidence by themselves. With no
reference, list the unresolved issues (Step 0). Use `analyze-sentry-feedback`
for Sentry feedback and `analyze-sentry-logs` for bulk structured-log triage.

Read the `track-sentry-findings` skill first and follow it throughout: it
holds the rules this skill shares with the other Sentry analysis skills, the
tracking review Step 2 runs, and the GitHub tracking Step 6 hands off to.

## `fix-issue` prerequisite contract

This skill may serve as a `fix-issue` intake prerequisite when an issue body
or comment contains the exact marker
`<!-- fix-issue-prerequisite: analyze-sentry-issue <numeric-id> -->`.
The only additional trusted marker author is `github-actions[bot]`, the login
used by the checked-in daily checker, declared here as `fix-issue` requires:

<!-- fix-issue-trusted-marker-author: github-actions[bot] -->

The argument is the numeric Sentry issue ID. A complete block from
`<!-- analyze-sentry-issue-findings:start -->` through
`<!-- analyze-sentry-issue-findings:end -->` in the same issue body is the
completion signal.

## Step 0: No reference given? List unresolved issues

When no issue reference is given or obvious from the conversation, list the
unresolved issues with `bin/snissue --list` instead of asking for one, and let
the user choose a row. Treat anything typed with the pick as triage notes. If
nothing is unresolved, say so and stop.

## Step 1: Resolve the reference

Resolve the reference to the numeric ID, short ID, permalink, status, and
substatus with `sentry issue view <reference> --fresh --json`. Tell the user
the short and numeric IDs in one line before fetching evidence, echoing any
triage notes so they know the notes were picked up.

If Sentry cannot find the issue, check the organization audit log for an
`issue.delete` entry naming its numeric ID:

```bash
sentry api 'organizations/artisanal-software/audit-logs/?event=issue.delete&per_page=100'
```

Report whether it was deleted or most likely aged out of retention, then
continue from the GitHub history in Step 2 alone.

## Step 2: Find the tracking issue and history

Review the tracking history as `track-sentry-findings` describes, listing
the tracking issues, canonical first, with
`bin/snissue --track <numeric-id>`, which leaves out issues the intake's
`github-actions[bot]` or the owner, `jubishop`, did not open. The daily
`bin/check-sentry-issues` placeholder is titled `Triage Sentry issue <shortId>`
or `Triage recurrence of Sentry issue <shortId>`. Search for the same failure
under other IDs with:

```bash
gh issue list --repo jubishop/podhaven --state all \
  --search 'label:sentry-issue,sentry-feedback <terms>'
bin/knowledge search "<terms>"
```

## Step 3: Fetch the evidence

Fetch the issue into an empty directory under the triage's working directory
with `.agents/scripts/sentry-cli/fetch_issue_bundle.sh`; its
[response contracts](../../scripts/sentry-cli/README.md) give the bundle's
files. Pass an event query only when the user scoped the investigation; if it
matches nothing, adjust the scope or report the absence.

Inspect enough events to explain meaningful variation across time, release,
environment, device, or other dominant clusters. Prefer in-app stack frames,
then the breadcrumbs just before the error. Record the relevant exception
details, tags, user and request context, release and commit, trace context,
replay links, and attachment metadata. Use tag distributions and event samples
to judge impact and whether the issue is isolated, recurring, or regressing.
When a linked trace could change the diagnosis, fetch its span context with
the helper's span depth option and analyze only the relevant path; otherwise
say what trace context was available without implying that the full trace was
analyzed.

When build history, attachments, structured logs, or MetricKit evidence could
change the conclusion, read
[PodHaven correlation](references/podhaven-correlation.md) and follow only the
relevant sections.

## Step 4: Trace the failure

Trace the failure through the current codebase: the implicated data flow,
assumptions, nearby callers, recent history, similar patterns, and existing
tests. If an event does not match the current tree, use stable symbol names
and history to explain the drift.

For a recurrence, or a failure that resembles a known fix, test each event's
build against the earlier fix as
[PodHaven correlation](references/podhaven-correlation.md#builds-and-known-fixes)
describes, and state each result. Events only from builds that predate the fix
are a stale build, not a new defect.

## Step 5: Synthesize

Lead with what failed and who it affects. Include:

- Direct observations from representative Sentry events and code inspection.
- Prior analysis from Step 2, and for a recurrence, the stale-build or
  incomplete-fix verdict with its ancestry results.
- The inferred root cause, confidence, and what would raise confidence.
- Material alternatives and why the evidence favors or rejects them.
- A code, operational, or monitor/defer recommendation with the relevant files,
  functions, and regression tests.
- Open questions only when their answers could change the decision.

Name any disagreement between evidence sources, or a failed correlation,
instead of silently picking one.

## Step 6: Track the findings in GitHub

Track the findings as `track-sentry-findings` describes, in
`jubishop/podhaven` with the `sentry-issue` label. Keep the exact marker
`<!-- sentry-issue:<numeric-id> -->`, by which `bin/check-sentry-issues`,
`bin/snissue`, and later runs find the issue, and use this body shape:

```markdown
<!-- sentry-issue:<numeric-id> -->
This issue tracks [Sentry issue `<shortId>`](<permalink>) (numeric issue ID `<numeric-id>`).

<!-- analyze-sentry-issue-findings:start -->
## Findings

- **Observed vs. expected:** <sanitized behavior>
- **Affected scope:** <builds, environments, users, frequency>
<the shared findings fields>

## Sentry record

- **Title:** <sanitized Sentry issue title>
- **Exception:** <type and mechanism>
- **Top in-app frames:** <symbolicated function names>
- **Seen:** <first and last seen in PT; event and user counts>
- **Builds:** <releases and their git-commit-hash values; environments>
- **OS:** <affected versions>

<the shared resolution sections>

## Sentry closeout

- When this issue's work is done, close [Sentry issue `<shortId>`](<permalink>)
  (numeric issue ID `<numeric-id>`) with
  `.agents/scripts/sentry-cli/close_sentry_issue.sh <numeric-id>` and the
  mode that fits, which fails unless Sentry recorded the closure:
  - `--commit <merge-commit-sha>` when a merged commit fixes it.
  - `--next` when it closes without a fix commit, such as a stale-build
    recurrence.
  - `--archive` when the error is accepted as expected behavior.
<the shared closeout handoff>
<!-- analyze-sentry-issue-findings:end -->
```
