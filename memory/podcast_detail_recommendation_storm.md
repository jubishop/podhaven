---
name: podcast-detail-observation-storm
description: PodcastDetail build-506 memory warning/watchdog investigation. The old "DB observation storm" framing is now suspect: repeated `observePodcastSeries` entry logs prove repeated task entry, not necessarily repeated GRDB yields. Reporter was not on recommendation sorting. Logging now distinguishes constructor/lifecycle churn from DB emissions; behavior fixes tracked in #357.
type: project
---

# PodcastDetail observation storm / lifecycle churn

**Status as of 2026-05-27**: open investigation. The 2026-05-27 build-506
incident produced a memory warning followed by a foreground watchdog kill, but
the prior "async DB observation emitted thousands of times" conclusion is no
longer safe. The hot log line was emitted at the top of
`PodcastDetailViewModel.observePodcastSeries`, before the `for await` loop, so
rate-limited repeats prove repeated entry into `observePodcastSeries` / task
creation or restart. They do **not** by themselves prove that one GRDB
`ValueObservation` yielded thousands of values.

The user was **not** using recommendation-score sorting during the 2026-05-27
incident. Do not treat recommendation sorting as the cause unless fresh logs
show it.

Behavior follow-up: **#357** tracks the two preferred fixes:

1. make `PodcastDetailViewModel.init` side-effect-free; and
2. make PodcastDetail list updates incremental through a first-class
   `PowerList` API.

## Incident facts

- Feedback `podhaven:7509371787`: "Memory warning why??", submitted
  2026-05-27 08:04:35 PT.
- Crash `PODHAVEN-3J`: `WatchdogTermination`, foreground, around
  2026-05-27 08:04:51 PT.
- Feedback `podhaven:7509373362`: "App just crashed", submitted after relaunch
  at 2026-05-27 08:05:10 PT.
- Build: TestFlight 506, commit `3b037fb1`, tag `v1.0b506`.
- Screen context: PodcastDetail for "Revisionist History" (podcast 21).
- First feedback context showed app memory around 3.08 GB and device free
  memory around 62.8 MB.
- After relaunch, app memory was back near 347 MB and device free memory around
  5.0 GB.

The rolling app log showed intense PodcastDetail logging immediately before the
kill. The important correction is where those lines were emitted:

- `observePodcastSeries` entry line: before the `for await` loop.
- `Updating observed series`: inside the `for await` loop.
- `transition` / `refreshEpisodeList` / `startObservation` lines: downstream
  of an observed value or state transition.

So next analysis must count **both** observation entries and loop yields.
Repeated entries with low per-task yield counts means lifecycle/task churn.
One stable VM/task with huge yield counts means actual DB/writer churn.

## Historical context

#293 documented an earlier PodcastDetail observation storm. Build-499
diagnostics showed genuine value changes in `PodcastSeriesDetail` during that
capture, often through the wide detail observation region:

- podcast row;
- every episode row for the open podcast; and
- each episode's `episodeEmbedding` existence projection.

That historical evidence is still useful, but it should not be blindly applied
to the 2026-05-27 incident. The build-506 evidence lacks per-yield counts and
the reporter was not on recommendation sorting. The embedding cache plan never
landed; it was abandoned. The old debounce plan was also abandoned and should
not be revived as the first fix without fresh proof.

## Current diagnostic logging

The 2026-05-27 logging pass is intended to settle the question next time:

- `PodcastDetailViewModel` now logs a stable `vm=<id>` diagnostic summary
  containing state, entry count, sort method, and observation task state.
- `PodcastDetailView` logs struct init, appear, and disappear with the VM
  summary, so discarded SwiftUI destination models can be distinguished from
  appeared models.
- `startObservation(_:caller:)` logs caller and task state when it skips or
  creates an observation task.
- `observePodcastSeries` logs entry and exit duration, yield count, and exit
  reason (`cancelled` vs `natural`).
- Per-yield `Updating observed series` logs include yield number and VM
  summary.
- same-id `.saved → .saved` transitions log which top-level field changed
  (`podcast`, `episodes`, or `tags`).
- transition storms log a one-shot warning with `Thread.callStackSymbols` when
  a VM crosses 50 transitions/sec.
- `RecommendationScoringCoordinator.refresh()` logs nil-snapshot, cache-hit,
  in-flight skip, and new-pass branches; `Recommendations.coordinator` has
  `.trace` level so those trace messages are actually written.

Interpretation guide:

- Many `init vm=N` lines with few or no matching `appear vm=N`, followed by
  observation entries for discarded VMs: constructor side effects.
- One appeared VM with many `observePodcastSeries` entries and `yields=0` or
  `yields=1` exits: observation task restart churn.
- One appeared VM with one long-lived `observePodcastSeries` and huge yield
  count: actual DB/writer churn.
- Recommendation coordinator trace absent or nil-snapshot only: recommendation
  sorting is not involved.

## Behavior fixes tracked by #357

### 1. Side-effect-free `PodcastDetailViewModel.init`

`PodcastDetailViewModel.init(state:)` should not start async work that can
outlive a discarded SwiftUI view/model. Current offenders:

- `startObservation(state.savedSeries?.id)`;
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
observation task and no share-artwork task.

### 2. Incremental PodcastDetail list updates

`refreshEpisodeList(from:)` currently rebuilds `episodeList.allEntries` on each
saved-series update. `PowerList.allEntries` always updates `baselineEntries`
and calls `scheduleEntriesUpdate()`, which cancels/recreates the projection
task. That is too blunt for observation-driven detail updates.

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

## What not to do

- Do not debounce `observePodcastSeries` as the first behavior fix.
- Do not assume GRDB emitted thousands of values from one observation until
  the new yield-count logging proves it.
- Do not assume recommendation sorting was involved in the 2026-05-27 report.
- Do not hide user-visible updates; detail updates should stay immediate.
- Do not mutate `PowerList.allEntries[id:]` from outside as a workaround. The
  computed setter schedules a full projection update; add an explicit API.

## Analysis workflow

Use the Sentry feedback skill for future feedbacks. For local log inspection,
use `.agents/skills/analyze-logs/scripts/log_summary.py`:

1. `--sessions`
2. `--session N`
3. `--call-sites`

The 2026-05-27 reference captures were downloaded to:

- `~/Library/Caches/analyze-sentry-feedback/podhaven-7509371787/`
- `~/Library/Caches/analyze-sentry-feedback/podhaven-7509373362/`

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
  PowerList updates.
- #293 — historical DB-observation storm investigation; useful context, but
  not definitive for build 506.
- #294 — FileLogHandler perf/rate-limit context.
- #296 — recommendation-engine full-library rescan sibling issue.
- #297 — `EmbeddingProcessor` FK-on-delete race found in older diagnostics.
- `memory/recommendation_sort_prewarming.md` — recommendation sorting runs on
  demand; do not assume background prewarming.
