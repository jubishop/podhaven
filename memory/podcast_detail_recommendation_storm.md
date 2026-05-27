---
name: podcast-detail-observation-storm
description: PodcastDetail memory warning / foreground watchdog kill. The build-507 incident (podhaven:7509841267) and its build-506 predecessors are conclusively constructor / lifecycle churn — SwiftUI re-evaluates the PodcastDetail destination thousands of times during a single Up Next → Podcasts navigation, and `PodcastDetailViewModel.init(state:)` starts an observation task and an artwork Task for every transient instance. Behavior fix tracked in #357 item 1. Existing diagnostics plus PR #359 are sufficient; no further detector work needed.
type: project
---

# PodcastDetail observation storm / lifecycle churn

**Status as of 2026-05-27**: cause established, behavior fix pending. The
2026-05-27 build-507 feedback `podhaven:7509841267` ("App just crashed after
memory warning") reproduced the build-506 incident with the new diagnostic
logging in place, and the logs unambiguously show **constructor / lifecycle
churn**: a single user navigation produced **~7,200 `PodcastDetailViewModel`
instances for the same podcast in 46 seconds**, of which only ~20 ever
appeared. Each transient VM runs the full constructor side-effect chain
(`startObservation(caller: init(state:))` → seed yield → `transition: saved →
saved, diff=[ episodes(0→184) tags(0→1) ]` → `refreshEpisodeList`) before
being garbage-collected, leaking allocations until iOS issues a memory
warning and then watchdog-terminates the foreground app.

The fix is **#357 item 1** — make `PodcastDetailViewModel.init(state:)`
side-effect-free. Item 2 (incremental `PowerList` updates) remains useful
follow-up work but is not what kills the app today.

## Incident facts

### 2026-05-27 build 507 (definitive)

- Feedback `podhaven:7509841267` ("App just crashed after memory warning"),
  submitted 2026-05-27 11:46:13 PT.
- Crash `PODHAVEN-3J`: `WatchdogTermination`, foreground, 11:45:54 PT — 19 s
  before the feedback, 5 s after the last log line.
- Build: TestFlight 507, commit `e6a396c5`. Contains the new diagnostic
  logging from `6aa87834` but no #357 behavior fix.
- Screen context: PodcastDetail for "Taylor Lorenz's Power User" (podcast 1),
  184 episodes.
- Trigger: at 11:45:08.019 PT the user calls `Navigation.showPodcast([1])`
  during an `upNext → podcasts` tab transition while a sheet is being
  dismissed. The storm starts in the same millisecond.

What the new diagnostics proved:

- VM IDs 1 → 7,210 created in 46 s (~156/s on average). Of those, ~7,180
  never had `performAppear()` called.
- 399 `startObservation` log lines, all with `caller=init(state:)` — direct
  proof of the constructor side-effect.
- 278 `observePodcastSeries` entries; each yields exactly once with `entries=0
  → 184` and exits. There is no single long-lived task with thousands of
  yields, so this is not GRDB writer churn.
- 91 `transition: saved → saved` warnings visible (rate-limiter dropped the
  rest); `caller=observePodcastSeries(_:)`, `entries=0`, `sort=newestFirst`,
  `diff=[ episodes(0→184) tags(0→1) ]` for all of them.
- Recommendation coordinator absent from the storm window
  (`sort=newestFirst`, no `Recommendations.coordinator` trace) — recommendation
  sorting is not involved.
- The per-VM transition-storm detector (50 transitions/sec threshold) did
  **not** fire. Each storm VM only transitions once; the storm is across
  instances. That's expected behavior given the threshold and is fine —
  PR #359 catches the suppression at the `FileLogHandler` layer instead
  (see below).
- Reference download: `~/Library/Caches/analyze-sentry-feedback/podhaven-7509841267/`.

### 2026-05-27 build 506 (precursors)

Same user, same code path, ~3 h 41 m earlier in the day on TestFlight 506
(commit `3b037fb1`, tag `v1.0b506`). Build 506 lacked the new diagnostics,
which is why those reports were initially ambiguous between "DB observation
storm" and "lifecycle churn":

- Feedback `podhaven:7509371787` ("Memory warning why??"), 08:04:35 PT;
  PodcastDetail for "Revisionist History" (podcast 21).
- Crash `PODHAVEN-3J` watchdog termination, foreground, 08:04:51 PT.
- Feedback `podhaven:7509373362` ("App just crashed") on relaunch, 08:05:10 PT.
- First feedback context: app memory ~3.08 GB, device free memory ~62.8 MB.
- Reference downloads: `~/Library/Caches/analyze-sentry-feedback/podhaven-7509371787/`
  and `podhaven-7509373362/`.

Build 507's logs retroactively explain the 506 reports: same lifecycle pattern,
different podcast.

## Current diagnostic logging

The 2026-05-27 logging pass (`6aa87834`, shipped in build 507) is now proven
sufficient to characterize this class of incident. Nothing further is needed
to ship #357. Inventory, for reference:

- `PodcastDetailViewModel` logs a stable `vm=<id>` summary on every relevant
  call (state, entry count, sort method, observation task state).
- `PodcastDetailView` logs struct `init`, `appear`, and `disappear` with the
  VM summary — discarded SwiftUI destination models are now distinguishable
  from appeared models.
- `startObservation(_:caller:)` logs the `caller` and whether it created or
  found an existing task. `caller=init(state:)` is the constructor side-effect
  signature.
- `observePodcastSeries` logs entry and exit duration, yield count, and exit
  reason (`cancelled` vs `natural`).
- Per-yield `Updating observed series` logs include yield number and VM
  summary.
- Same-id `.saved → .saved` transitions log which top-level field changed
  (`podcast`, `episodes`, or `tags`) via the `diff=[...]` suffix.
- A per-VM transition-storm warning fires once with `Thread.callStackSymbols`
  when a single VM crosses 50 transitions/sec. By design, this catches
  yield-per-VM storms (one task emitting many values), not cross-VM
  lifecycle storms (many VMs each emitting once) — the build-507 incident
  is the latter, so this detector correctly stays silent.
- `RecommendationScoringCoordinator.refresh()` logs nil-snapshot, cache-hit,
  in-flight skip, and new-pass branches; `Recommendations.coordinator` has
  `.trace` level so those trace messages are actually written.

Interpretation guide (proven against build-507 logs):

- Many `init vm=N` lines with few or no matching `appear vm=N`, **and**
  `startObservation: ... caller=init(state:)` for every one of them:
  **constructor side effects** (this incident).
- One appeared VM with many `observePodcastSeries` entries and `yields=0` or
  `yields=1` exits: observation task restart churn.
- One appeared VM with one long-lived `observePodcastSeries` and huge yield
  count: actual DB/writer churn.
- Recommendation coordinator trace absent or nil-snapshot only: recommendation
  sorting is not involved.

## Companion log-side instrumentation: PR #359

PR #359 (FileLogHandler storm warnings, open at time of writing) is a
companion to the diagnostics above. It detects when a single `(file, line)`
call site is having entries dropped by the rate limiter and emits one
`.warning` per 60 s cooldown carrying suppressed-count and the originating
`Thread.callStackSymbols`. For this incident it would have produced one
`FileLogHandler storm: PodcastDetailViewModel.swift:834 ...` warning visible
in Sentry directly — no feedback round-trip required to know a storm is
happening.

PR #359 is generically useful (catches any future log-suppression storm in
any subsystem). It does **not** replace the behavior fix in #357 and there
is no need to add a third, behavior-specific aggregate counter inside
`PodcastDetailViewModel`. The existing per-VM `vm=N` + `caller=...` logging
is enough to verify a fix and catch regressions.

## Behavior fixes tracked by #357

### 1. Side-effect-free `PodcastDetailViewModel.init` (ship this first)

`PodcastDetailViewModel.init(state:)` must not start async work that can
outlive a discarded SwiftUI view/model. Current offenders (build 507):

- `startObservation(state.savedSeries?.id)` at line ~497;
- the share-artwork `Task { ... imagePipeline.image(for:) ... }`.

Preferred shape:

- keep `init` limited to synchronous owned-state setup;
- move observation startup into the kept model's lifecycle, likely
  `performAppear()`;
- move share-artwork loading into an idempotent lifecycle helper;
- keep `startObservation` idempotent and prompt;
- keep `disappear()` responsible for canceling observation and recommendation
  scoring.

The target behavior is that a VM initialized but never appeared starts no
observation task and no share-artwork task. Concretely: after the fix, the
build-507 trigger (`Navigation.showPodcast([1])` during an Up Next →
Podcasts transition) must produce at most one `init: vm=N` whose VM ID is
followed by `appear: vm=N` and exactly one
`observePodcastSeries: entering` / `yield=1` / `transition: saved → saved`
chain. Anything more means the constructor still has side effects.

### 2. Incremental PodcastDetail list updates

`refreshEpisodeList(from:)` currently rebuilds `episodeList.allEntries` on each
saved-series update. `PowerList.allEntries` always updates `baselineEntries`
and calls `scheduleEntriesUpdate()`, which cancels/recreates the projection
task. That is too blunt for observation-driven detail updates, even after
item 1 removes the volume.

Do **not** skip updating rows. Instead, skip only the expensive projection
recompute when membership/order/filter/search are unchanged.

Preferred shape:

- add a first-class `PowerList` API such as
  `updateEntries(_:projectionInvalidated:)`;
- when projection is not invalidated, update `baselineEntries` and patch
  `_allEntries` / `filteredEntries` by ID;
- when projection is invalidated, keep the existing schedule/recompute path.

For PodcastDetail, projection invalidation must include:

- inserts/deletes/identity changes (`ListedEpisode.id` is `MediaGUID`);
- current sort key changes (`pubDate`, `creationDate`, `duration`,
  `finishDate`, `queueDate`, or recommendation snapshot behavior);
- current filter key changes (`finishDate`, `queueDate`);
- active search key changes (`searchableString`, currently title plus podcast
  title for saved detail rows).

Visible non-projection fields should still patch immediately without
resorting/refiltering when they do not affect the current projection:

- `currentTime`;
- `cacheStatus`;
- `saveInCache`;
- `queueOrder` unless it affects the current projection;
- `rating` unless it affects recommendation behavior;
- `hasEmbedding` unless it affects recommendation behavior;
- image/title display fields; title also invalidates active search.

## Historical context

#293 documented an earlier PodcastDetail observation storm. Build-499
diagnostics showed genuine value changes in `PodcastSeriesDetail` during that
capture, often through the wide detail observation region (podcast row,
every episode row for the open podcast, each episode's `episodeEmbedding`
existence projection).

That historical evidence is still useful, but is **not** the cause of the
2026-05-27 incidents. Build-507 logs proved a different mechanism
(constructor / lifecycle churn). The old embedding-cache plan never landed
and was abandoned. The old debounce plan was also abandoned and should not
be revived.

## What not to do

- Do not add another behavioral storm detector inside
  `PodcastDetailViewModel`. The existing `vm=N`, `caller=...`, and
  `transition diff=[...]` logging is sufficient and PR #359 covers the
  generic log-suppression signal.
- Do not debounce `observePodcastSeries`. The fix is to not start the
  observation at all on a VM that never appears.
- Do not assume GRDB emitted thousands of values from one observation —
  build-507 diagnostics conclusively show one yield per VM.
- Do not assume recommendation sorting was involved — it wasn't, in any
  2026-05-27 incident on this user.
- Do not hide user-visible updates; detail updates must stay immediate.
- Do not mutate `PowerList.allEntries[id:]` from outside as a workaround.
  The computed setter schedules a full projection update; add an explicit
  API per #357 item 2.

## Analysis workflow

Use the `analyze-sentry-feedback` skill for future feedbacks. For local log
inspection of the downloaded NDJSON, use
`.agents/skills/analyze-logs/scripts/log_summary.py`:

1. `--sessions` to find the launch containing the feedback timestamp.
2. `--session N` to scope to that launch.
3. `--call-sites` to surface chatty `(file, line)` even when no warnings
   fire.
4. `--around <feedback_ms> --window-ms 60000 [--min-level warning] [--oneline]`
   to read the immediate timeline around the event.

For storm characterization specifically, the cross-VM signal lives in the
`vm=N` field of `init:` / `appear:` / `transition:` / `observePodcastSeries:`
messages. Counting distinct `vm=N` values seen in a 60-second window is the
fastest way to size a storm; counting `caller=init(state:)` occurrences
under `startObservation` proves the constructor side-effect.

## Key files

- `PodHaven/Views/Podcasts/Models/PodcastDetailViewModel.swift`
- `PodHaven/Views/Podcasts/PodcastDetailView.swift`
- `PodHaven/Views/Components/PowerList.swift`
- `PodHaven/Environment/Navigation.swift`
- `PodHaven/Database/Models/ListableEpisode.swift`
- `PodHaven/Database/Models/ListablePodcastEpisode.swift`
- `PodHaven/Database/DisplayModels/ListedEpisode.swift`
- `PodHaven/Recommendations/ViewUtility/RecommendationScoringCoordinator.swift`
- `PodHaven/Logging/Handlers/FileLogHandler.swift`

## Related

- #357 — behavior task for side-effect-free detail init and incremental
  `PowerList` updates. Item 1 is the active fix.
- #359 — FileLogHandler storm warnings (open PR). Complementary, ships
  log-side suppression detection.
- #293 — historical DB-observation storm investigation; useful context, but
  not the cause of the 2026-05-27 incidents.
- #294 — FileLogHandler perf/rate-limit context.
- #296 — recommendation-engine full-library rescan sibling issue.
- #297 — `EmbeddingProcessor` FK-on-delete race found in older diagnostics.
- `memory/recommendation_sort_prewarming.md` — recommendation sorting runs on
  demand; do not assume background prewarming.
