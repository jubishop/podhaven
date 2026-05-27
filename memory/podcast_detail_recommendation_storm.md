---
name: podcast-detail-observation-storm
description: PodcastDetail observation storm — wide `podcastSeriesDetail` region re-fires on any episode/embedding write, hammering `observePodcastSeries`/`transition` at hundreds per second. Root cause RESOLVED 2026-05-20 (#293). Debounce fix ABANDONED, #293 closed NOT_PLANNED 2026-05-21. RECURRED 2026-05-27 on build 506 and escalated to a fatal watchdog termination (PODHAVEN-3J). Bug is active and now fatal.
type: project
---

# PodcastDetail observation storm — open investigation

**Status as of 2026-05-27**: Root cause known and confirmed three times. The
planned debounce fix was abandoned (#293 closed `NOT_PLANNED` 2026-05-21).
Recurred today on build 506 / commit `3b037fb1` and **escalated from "app
pegged" to a fatal `WatchdogTermination` (`PODHAVEN-3J`)** while in the
foreground. Read this first before doing anything in `PodcastDetailViewModel`
or `Observatory.podcastSeriesDetail`.

## The bug

`Observatory.podcastSeriesDetail` is a GRDB `ValueObservation` whose tracked
region is very wide: the `podcast` row **plus every episode row plus every
episode's `episodeEmbedding`** (`ListableEpisode.databaseSelection` pulls
`episodeEmbedding` in via `EpisodeEmbedding.existsSelectable`). Any write to
any of those rows for the open podcast re-fires the whole-detail observation,
which drives `PodcastDetailViewModel.observePodcastSeries` → `transition` —
producing same-shape `saved → saved` transitions where `Equatable` correctly
sees a real diff in a non-displayed sub-field (commonly `episodeEmbedding`
flapping or live episode-row churn).

`PodcastSeriesDetail.Equatable` is sound and `removeDuplicates()` on the
observation is doing its job — when it yields, the value really did change.
The defect is the **tracked region**, not the equality.

Storm signature — `.debug` lines that hammer at the rate of the writer:

- `observePodcastSeries` entry — "observePodcastSeries: entering for <id>"
  (post 2026-05-27 logging; older builds said "Observing podcast series with
  ID: <id>")
- inside the for-await — "Updating observed series: …"
- `transition`'s same-id diff — post 2026-05-27, a `.warning` "transition:
  same-id non-equal saved → saved, diff=[…]" naming which sub-field differs
- `startObservation` — "already active" guard fires on each cycle

No error-level entries: every line in the storm proper is `.debug`. Nothing
alerts. The 2026-05-27 build adds a high-frequency `.warning` (transition
>50/sec) that captures a stack trace once — see "Logging instrumentation"
below.

## History

- **#274 (original report).** Fix shipped only plan items #1–#3, the
  recommendation *scoring* coalescer (commit `0cc82c8c`, PR #275). Plan item
  #4 — the observation storm itself — was deferred and never shipped.
- **Recurrence on build 498** (commit `967ddf79`, tag `v1.0b498`) at
  ~178 emissions/s. Sentry feedbacks `podhaven:7493496709`,
  `podhaven:7493497368` (2026-05-19). Tracked as **#293**. FileLogHandler perf
  tech-debt spun off as **#294**.
- **Build 499 diagnostic run (2026-05-20)** — TestFlight build from commit
  `8a4aa613`, carrying the `c45e2908` probes (`WriteProbe` + emission-diff
  probe). The emission-diff probe **named the root cause**: every emission was
  a genuine sub-field change (`episode 131531 content changed`, `podcast row
  changed`, `episode count 1 → 509`). Capture was mild because the user
  didn't sit on a single hot podcast for long — 24 re-emissions in ~105 s.
- **2026-05-21**: **#293 closed `NOT_PLANNED`.** No PR linked to the closure.
  The emission-diff probe was removed in PR #312 (commit `6e14c8a2`) with the
  message *"The fix it verified has been abandoned"*. `WriteProbe` was kept
  as a permanent debug facility. From this point forward there is **no
  detection mechanism in the binary**.
- **Recurrence on build 506** (commit `3b037fb1`, 2026-05-27) — Sentry
  feedbacks `podhaven:7509371787` + `podhaven:7509373362` and crash
  `PODHAVEN-3J` (`WatchdogTermination`, `mechanism=watchdog_termination`,
  in_foreground=true) at 08:04:51 PT. Reporter was on "Revisionist History"
  (podcast 21) — not on recommendation sort, no active downloads visible in
  the log. Storm sustained ~250 entries/sec at four log sites for at least
  the 6 minutes covered in the rolling buffer (Sessions 30 + 31). App memory
  reached **3.08 GB** with free memory at **62.8 MB** before the kill.
  FileLogHandler rate limiter suppressed ~38,600 entries across the storm
  window — the only reason the log is analyzable.

## Root cause — confirmed (Case 1: real writes through a too-wide tracked region)

Already proven on build 499: every emission carries a genuine sub-field
change. The 2026-05-27 incident is the same path, denser writer side. The
specific writer hasn't been pinned for today's incident (no
`recommendationScore` sort, so the prime suspect — `EmbeddingProcessor`
churning `episodeEmbedding` rows for the open podcast — is plausible but
unconfirmed without a fresh capture from the new logging).

What is NOT the cause: `removeDuplicates()` is correct;
`PodcastSeriesDetail.Equatable` is sound; SwiftUI view re-render is not the
driver (the recurrence happened with no rec-sort and the per-call-site rate
matches a DB-write cadence, not a 120 Hz display cadence). The 2026-05-20
analysis stands.

## Fix — debounce the observation (spec lives in #293)

Trailing-edge debounce on the emissions from
`observatory.podcastSeriesDetail` inside
`PodcastDetailViewModel.observePodcastSeries`'s `for try await` loop. Route
non-nil yields through the existing `Debounce` utility; **keep the
`nil`/deletion path immediate**. A time debounce caps the
emission→`transition` rate regardless of writer.

Disproven alternatives (do not waste another cycle on these):

- **Narrowing the tracked region.** `hasEmbedding` and `currentTime` are both
  rendered by the detail screen (`EpisodeListView.swift:87`
  `.embeddingPending`; `durationText` shows live `currentTime`). The
  observation legitimately reads those columns. No dead column to drop.
- **Tightening `Equatable`.** Synthesized `Equatable` is sound; the diffs are
  real DB changes.
- **Debouncing the shared `Observatory.observe`.** Would mute many unrelated
  observations and risk staleness on cheap ones.

The full single-source spec — root cause, why the column drop fails, the
exact debounce placement, the regression test (a fake observatory that emits
identical-shape-but-different-field values at a configurable rate, asserting
`transition` is called at most once per debounce window) — is the **#293
issue body**. The issue is closed; reopen or supersede it before working the
fix.

Intermediate refactors landed since the doc was written but **did NOT touch
the storm**: #303 (extract recommendation scoring), #321 (on-demand sort),
#326 (shared `RecommendationScoringCoordinator`), #336, #344, #350, #351.

## Logging instrumentation as of 2026-05-27

Added during the 2026-05-27 investigation (no PR yet — uncommitted on `main`):

- **`PodcastDetailViewModel.startObservation(_:caller:)`** — `#function`
  caller token + prior task state (`nil` vs `cancelled`) when a fresh task is
  created. The "already active" line now carries the caller token too. Will
  pin which call site is hammering startObservation next time.
- **`PodcastDetailViewModel.observePodcastSeries`** — entry log + `defer`
  block that reports `duration`, `yields` (for-await iterations), and
  `reason` (`cancelled` vs `natural`). Confirms whether the for-await is
  one-shotting (`yields=1, reason=natural`), being externally cancelled
  (`reason=cancelled`), or running long.
- **`PodcastDetailViewModel.transition`** — when state and newState are both
  `.saved` with the same id, logs a `.warning` listing which sub-field
  (`podcast` / `episodes(N→M)` / `tags(N→M)`) failed equality. Closes the
  "what's drifting" question without re-shipping the emission-diff probe.
  Also a one-shot storm guard that fires a single `.warning` with the full
  `Thread.callStackSymbols` the moment transitions cross 50/sec — gives us
  the live call stack of whatever is driving the cascade. Per-instance
  `transitionSamples: [ContinuousClock.Instant]` (sliding 1 s window) backs
  the guard.
- **`PodcastDetailViewModel.refreshEpisodeList`** — debug per `.allEntries`
  assignment with the entry count, surfaces PowerList churn cadence.
- **`RecommendationScoringCoordinator.refresh()`** — `.trace` at each
  early-return branch (nil snapshot / cache hit / in-flight match) and
  `.debug` when a fresh pass kicks. New `LogSubsystem.Recommendations.coordinator`
  case.

Still alive from `c45e2908`: **`WriteProbe`** in `AppDB._onDisk`, gated by
the `enableWriteProbe` user setting in Settings → Debug. Toggle it on before
walking into a detail view next time and we'll see per-statement table-write
events with stack traces. Do NOT revert.

Removed and not coming back unless re-staged: emission-diff probe in
`observePodcastSeries` (PR #312, commit `6e14c8a2`). The new transition diff
log above subsumes its function.

## Next step

1. **Reopen #293** (or open a successor issue) — closure as `NOT_PLANNED` was
   premature; the bug just killed the app.
2. **Implement the debounce fix** per the #293 spec. Regression test gates
   it. Reference the 2026-05-27 watchdog incident
   (`PODHAVEN-3J` / feedbacks 7509371787, 7509373362) in the PR.
3. **Ship a TestFlight build carrying both the fix and the 2026-05-27
   logging additions.** Confirm via a fresh capture that:
   - the `transition` >50/sec warning never fires;
   - `observePodcastSeries` `yields` and `duration` look sane;
   - the same-id transition diff warning doesn't fire either.
4. Once confirmed clean for at least one full TestFlight rev, decide whether
   to keep the 2026-05-27 logging or trim it. The storm guard + transition
   diff are cheap; the per-yield duration/yields/reason debug lines are
   chatty and worth gating behind a setting if we keep them long-term.
5. Promote `enableWriteProbe` from Settings → Debug into the standard
   pre-TestFlight checklist — turning it on before opening a hot podcast is
   the fastest way to find next writer.

Analyse logs with the `analyze-logs` `log_summary.py` script: `--sessions` →
`--session N` → `--call-sites`. The 2026-05-27 capture lives at
`~/Library/Caches/analyze-sentry-feedback/podhaven-7509373362/` and is a
useful reference shape for next time.

## Key references

- `Observatory.observe` / `Observatory.podcastSeriesDetail` —
  `PodHaven/Database/Observatory.swift` (`observe` =
  `ValueObservation.tracking(block).removeDuplicates().values(in:)`).
- `observePodcastSeries`, `transition`, `startObservation`,
  `refreshEpisodeList` —
  `PodHaven/Views/Podcasts/Models/PodcastDetailViewModel.swift`.
- `PodcastSeriesDetail` = `podcast` + `episodes: IdentifiedArrayOf<ListableEpisode>`
  + `tags`, synthesized `Equatable`.
- `RecommendationScoringCoordinator.refresh` —
  `PodHaven/Recommendations/ViewUtility/RecommendationScoringCoordinator.swift`.
- `WriteProbe` — `PodHaven/WriteProbe.swift` (gated by `enableWriteProbe`
  user setting).
- `FileLogHandler` rate limiter — `PodHaven/Logging/Handlers/FileLogHandler.swift`,
  per-`(file,line)` token bucket. Without it the 2026-05-27 capture would not
  be analyzable.

## Related

- [[recommendation_engine_full_library_rescan]] — #296, sibling bug: same
  architectural weakness (a SwiftUI observation triggering uncoalesced heavy
  work), different loop. Either alone pegs the app.
- [[recommendation_sort_prewarming]] — prewarming behaviour any fix must
  preserve.
- [[observation_broadcast_viewmodel]] — Broadcast `access()`/`withMutation()`
  cycle quirks under `@Observable`; relevant if a future fix touches the
  observation plumbing.
- [[device_debug_builds_break_background_scheduling]] — no on-device
  debugging; TestFlight only.
- [[build_variants_dev_debug_release]] — why `log.ndjson` exists only on
  device Release builds.
- #297 — `EmbeddingProcessor` FK-on-delete race, found in the same build-499
  log.
- #294 — FileLogHandler perf tech-debt spinoff (still open).
