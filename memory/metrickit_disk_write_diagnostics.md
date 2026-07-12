---
name: metrickit-disk-write-diagnostics
description: Why we drop MXDiskWriteException MetricKit diagnostics in Sentry, and why PODHAVEN-3W recurrences are not a PR #355 regression
type: reference
---

`MXDiskWriteException` is a MetricKit diagnostic that fires when the app's
**cumulative logical disk writes over a ~24h window cross a fixed threshold**
(~1 GiB; the reported `totalWritesCaused` clusters at the threshold floor, so
the value is not a severity signal). For a podcast app the dominant writer is
routine **episode-audio downloads** (`CacheBackgroundDelegate.urlSession`), so
this diagnostic is expected noise for heavy users, not an actionable defect.

## What we do about it

`AppLauncher.configureSentry()` sets `options.beforeSend = sentryBeforeSend`
(the generic event-filter hook), which returns `nil` for any event whose
exception mechanism `type == "mx_disk_write_exception"`. Hang
(`mx_hang_diagnostic`), CPU (`mx_cpu_exception`), and crash MetricKit
diagnostics still flow. `MetricKitMonitor` independently logs every
diagnostic — including disk-write — at `.notice` with the raw
`jsonRepresentation()` in metadata, so the forensic payload is retained in the
NDJSON logs even though the Sentry issue is suppressed.

## PODHAVEN-3W history (don't re-litigate)

PODHAVEN-3W is the auto-filed Sentry issue for this diagnostic (titled
`DatabaseCursor.forEach`, grouped off the `RefreshManager.performRefresh` →
`Repo.allPodcastSeries` read path in MetricKit's merged call tree). PR #355
("Batch lastUpdate writes in RefreshManager to stop DB write storm") closed it,
but it **recurred on builds 534 and 536** — and `git merge-base
--is-ancestor` confirms the #355 commit (`3b037fb`) **is present** in those
builds. That is not a regression: #355 fixed the write *storm* (transaction
count, the UI-stall symptom that was PODHAVEN-3X), which transaction batching
cannot reduce *byte volume*. The diagnostic was always going to keep tripping
for heavy downloaders. Treat future PODHAVEN-3W-shaped reports as monitor /
won't-fix, not as a broken #355.

The separate, real perf inefficiency the same investigation surfaced — the
`allPodcastSeries` `.including(all:)` full-episode prefetch on every refresh
cycle — is tracked in issue #502. It is CPU/memory hygiene (OOM-jetsam family,
cf. #274) and does **not** meaningfully move the disk-write diagnostic.

## MetricKit delivery gotcha

MetricKit delivers diagnostics at the **next launch** after the incident. The
Sentry event timestamp ≈ that launch time (e.g. `app_start_time` matches the
event time), and the breadcrumbs / attachments are the launch session, not the
write window. When correlating a MetricKit diagnostic to local logs, lead with
`--category` over the whole NDJSON file, not `--around` the event time.
