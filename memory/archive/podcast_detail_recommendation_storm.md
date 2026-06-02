---
name: podcast-detail-observation-storm
description: PodcastDetail memory warning / foreground watchdog kill. The build-507 incident (podhaven:7509841267) and its build-506 predecessors were conclusively constructor / lifecycle churn — SwiftUI re-evaluated the PodcastDetail destination thousands of times during a single Up Next → Podcasts navigation, and `PodcastDetailViewModel.init(state:)` started an observation task and an artwork Task for every transient instance. Behavior fix shipped (issue #357) by moving observation startup and share-artwork loading to `performAppear`. The verbose per-VM diagnostics were removed when the fix landed; PR #359's generic FileLogHandler storm warning is the complementary log-side backstop.
type: project
status: resolved
--- / lifecycle churn

**Archived 2026-05-29**: resolved and closed out. The behavior fix (#357)
shipped and the follow-up that extracted the shared appear/observation
lifecycle into `DetailLifecycle` (and made the detail view models'
`init`/`appear`/`disappear` uniformly side-effect-free) landed on top of it.
Kept for historical reference; no active workstream remains.

**Status as of 2026-05-27**: cause established and fix shipped. The
2026-05-27 build-507 feedback `podhaven:7509841267` ("App just crashed after
memory warning") reproduced the build-506 incident with diagnostic logging
in place, and the logs unambiguously showed **constructor / lifecycle
churn**: a single user navigation produced **~7,200 `PodcastDetailViewModel`
instances for the same podcast in 46 seconds**, of which only ~20 ever
appeared. Each transient VM ran the full constructor side-effect chain
(`startObservation(caller: init(state:))` → seed yield → `transition: saved →
saved, diff=[ episodes(0→184) tags(0→1) ]` → `refreshEpisodeList`) before
being garbage-collected, leaking allocations until iOS issued a memory
warning and watchdog-terminated the foreground app.

The fix shipped in #357: `PodcastDetailViewModel.init(state:)` is now
side-effect-free. Observation startup flows through `performAppear` →
`attemptObservation` → `transition(...)` → `startObservation(...)`, and
share-artwork loading is an idempotent `loadShareArtworkIfNeeded()` helper
called from `performAppear`. After the fix, only the appeared VM owns
long-lived async work; transient SwiftUI-reevaluation instances do nothing
beyond synchronous owned-state setup.

The originally-proposed companion workstream (incremental `PowerList`
updates) was retired without being implemented: with `init` no longer
firing observation, `refreshEpisodeList` runs once per appear instead of
thousands of times per navigation, so the per-update rebuild cost is no
longer a problem in evidence. If production logs or profiles later show a
real per-update cost on a single appeared VM, file a fresh issue at that
point — do not revive item 2 speculatively.

## Incident facts

### 2026-05-27 build 507 (definitive)

- Feedback `podhaven:7509841267` ("App just crashed after memory warning"),
  submitted 2026-05-27 11:46:13 PT.
- Crash `PODHAVEN-3J`: `WatchdogTermination`, foreground, 11:45:54 PT — 19 s
  before the feedback, 5 s after the last log line.
- Build: TestFlight 507, commit `e6a396c5`. Contains the diagnostic
  logging from `6aa87834` but no #357 behavior fix.
- Screen context: PodcastDetail for "Taylor Lorenz's Power User" (podcast 1),
  184 episodes.
- Trigger: at 11:45:08.019 PT the user calls `Navigation.showPodcast([1])`
  during an `upNext → podcasts` tab transition while a sheet is being
  dismissed. The storm starts in the same millisecond.

What the diagnostics proved:

- VM IDs 1 → 7,210 created in 46 s (~156/s on average). Of those, ~7,180
  never had `performAppear()` called.
- 399 `startObservation` log lines, all with `caller=init(state:)` — direct
  proof of the constructor side-effect.
- 278 `observePodcastSeries` entries; each yielded exactly once with
  `entries=0 → 184` and exited. There is no single long-lived task with
  thousands of yields, so this is not GRDB writer churn.
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

## Diagnostic logging (build 507, since removed)

The 2026-05-27 logging pass (`6aa87834`, shipped in build 507) characterized
this class of incident. **That verbose per-VM instrumentation was removed when
the side-effect-free init landed** — the `vm=<id>` summary, the
`startObservation(caller:)` argument, the `transition diff=[...]` suffix, and
the per-VM transition-storm detector no longer exist in current builds. The
inventory below describes the build-507 logs only, for interpreting the
archived captures referenced under "Incident facts":

- `PodcastDetailViewModel` logs a stable `vm=<id>` summary on every relevant
  call (state, entry count, sort method, observation task state).
- `PodcastDetailView` logs struct `init`, `appear`, and `disappear` with the
  VM summary — discarded SwiftUI destination models are now distinguishable
  from appeared models.
- `startObservation(_:caller:)` logged the `caller` and whether it created or
  found an existing task. (The `caller` argument and this logging were removed
  alongside the fix.)
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
  was the latter, so this detector correctly stayed silent.
- `RecommendationScoringCoordinator.refresh()` logs nil-snapshot, cache-hit,
  in-flight skip, and new-pass branches; `Recommendations.coordinator` has
  `.trace` level so those trace messages are actually written.

Interpretation guide (proven against build-507 logs):

- Many `init vm=N` lines with few or no matching `appear vm=N`, **and**
  `startObservation: ... caller=init(state:)` for any of them:
  **constructor side effects** (the regression signature for #357).
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
`Thread.callStackSymbols`. For the original 2026-05-27 incident it would have
produced one `FileLogHandler storm: PodcastDetailViewModel.swift:NNN ...`
warning visible in Sentry directly — no feedback round-trip required to know
a storm is happening.

PR #359 is generically useful (catches any future log-suppression storm in
any subsystem). It does **not** replace the behavior fix in #357 and there
is no need to add a behavior-specific aggregate counter inside
`PodcastDetailViewModel`. With the verbose per-VM diagnostics now removed,
`LifecycleTests` is the primary regression guard and PR #359's generic
log-suppression warning is the production backstop.

## Behavior fix shipped: side-effect-free init (#357)

`PodcastDetailViewModel.init(state:)` was previously starting async work
that could outlive a discarded SwiftUI view/model:

- `startObservation(state.savedSeries?.id)`;
- a `Task { ... imagePipeline.image(for:) ... }` for share artwork.

Post-fix shape:

- `init` is limited to synchronous owned-state setup (`state` plus a
  `refreshEpisodeList(from:)` seed for a non-empty saved series). No `Task`,
  no `startObservation`, no image pipeline call, no diagnostic logging.
- Observation startup flows through `performAppear` → `attemptObservation`
  → `transition(...)` → `startObservation(...)`. Only the kept (appeared)
  VM ever owns the observation task.
- Share-artwork loading lives in `loadShareArtworkIfNeeded()` — idempotent
  (no-ops once `shareArtwork` is populated or a load is in flight), called
  from `performAppear`, cancellation-aware via a stored task handle.
- `disappear()` continues to cancel observation and recommendation scoring.

Target behavior, verified by `LifecycleTests`:

- A VM initialized but never appeared starts no observation task and no
  share-artwork task, for any seed shape (saved displayed, listed bridge,
  unsaved displayed, unsaved series).
- The appeared VM starts observation promptly and loads share artwork
  exactly once across repeated `performAppear` calls.

Regression guard: the side-effect-free init is pinned by `LifecycleTests`
(transient inits start no observation/share-artwork work; only the appeared
VM does). The verbose per-VM production logging that originally caught this
(`vm=N`, `startObservation ... caller=init(state:)`) was removed with the
fix, so a production recurrence now surfaces via PR #359's generic
`FileLogHandler` storm warning rather than a bespoke `caller=` signal.

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

- Do not re-add async work to `PodcastDetailViewModel.init(state:)`. SwiftUI
  destination re-evaluation will resurrect the storm.
- Do not add a behavioral storm detector inside `PodcastDetailViewModel`.
  `LifecycleTests` pins the side-effect-free init and PR #359 covers the
  generic log-suppression signal.
- Do not debounce `observePodcastSeries`. The fix is not to start the
  observation at all on a VM that never appears.
- Do not assume GRDB emitted thousands of values from one observation —
  build-507 diagnostics conclusively show one yield per VM.
- Do not assume recommendation sorting was involved — it wasn't, in any
  2026-05-27 incident on this user.
- Do not hide user-visible updates; detail updates must stay immediate.
- Do not preemptively rewrite `PowerList` to be incremental. The original
  proposal (per-id patching with a `projectionInvalidated` flag) was
  retired; it was solving a problem that depended on observation churn that
  no longer exists. Revisit only with new evidence from a single appeared
  VM.

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
under `startObservation` proves a constructor-side-effect regression.

## Key files

- `PodHaven/Views/Podcasts/Models/PodcastDetailViewModel.swift`
- `PodHaven/Views/Podcasts/PodcastDetailView.swift`
- `PodHaven/Environment/Navigation.swift`
- `PodHaven/Recommendations/ViewUtility/RecommendationScoringCoordinator.swift`
- `PodHaven/Logging/Handlers/FileLogHandler.swift`
- `PodHavenTests/ViewModelTests/PodcastDetailViewModelTests/LifecycleTests.swift`

## Related

- #357 — behavior task for side-effect-free detail init. **Fixed**.
- #359 — FileLogHandler storm warnings (open PR). Complementary, ships
  log-side suppression detection.
- #293 — historical DB-observation storm investigation; useful context, but
  not the cause of the 2026-05-27 incidents.
- #294 — FileLogHandler perf/rate-limit context.
- #296 — recommendation-engine full-library rescan sibling issue.
- #297 — `EmbeddingProcessor` FK-on-delete race found in older diagnostics.
- `memory/recommendation_sort_prewarming.md` — recommendation sorting runs on
  demand; do not assume background prewarming.
