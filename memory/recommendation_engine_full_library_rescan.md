---
name: recommendation-engine-full-library-rescan
description: Active investigation (#296) — RecommendationEngine rescans the entire ~95.5K-episode library on every Unqueued-list display / tab switch, and the result-marshalling lands on @MainActor, pegging the app. Distinct from the #293 PodcastDetail storm; same architectural pattern.
type: project
---

# RecommendationEngine full-library rescan (#296)

Active investigation. Root cause confirmed from a diagnostic TestFlight build
and a code read.

## The bug

`EpisodesListViewModel.startDisplayObservation` (the Unqueued list) →
`kickRecommendationFetch` → `RecommendationEngine.scoreEpisodes` /
`embeddings(for:)` loads and scores the **entire episode library** on every
list display and every tab switch back to Episodes. On a large library each
pass is 0.4–2.2 s of CPU plus repeated 0.4–1.6 s ~95K-row SQLite reads. Rapid
tab navigation stacks them; lists won't load, queue/unqueue taps take several
seconds. No crash, no error-level event.

## Evidence

Sentry feedback `podhaven:7495117741` + `podhaven:7495118557` (build `1.0+499`,
commit `8a4aa613`, 2026-05-20). In the 71 s cold-launch incident session: 9
full `embeddings(for:)` loads of ~95,500 embeddings (0.40–1.64 s each) + 4 full
`topRecommendations` passes (0.64–2.17 s each). `WriteProbe` showed DB writes
normal (~2.6 commits/s) — the "DB slammed" feeling is heavy *reads*, not writes.

## Root cause (two compounding parts)

1. **No coalescing.** `kickRecommendationFetch` re-fires on every Unqueued-list
   display observation / tab switch, with no debounce or dedup of unchanged
   inputs. The #274 scoring coalescer does not cover this path.
2. **Each fetch is O(entire library).** `scoreEpisodes` scores all ~95.5K
   candidates for a top-10; `embeddings(for:)` re-reads + re-decodes the full
   embedding set from SQLite every call, with no in-memory cache.

Cost scales with total library size — invisible on small / Simulator DBs,
severe on the reporter's 96,037-episode library.

## Verified mechanism — why a `.utility` task still freezes the UI

Confirmed in code (`EpisodesListViewModel.swift`). The view model is
`@Observable @MainActor`. `kickRecommendationFetch` line 364 is
`Task(priority: taskPriority(.utility)) { … }` — a **non-detached** `Task`
created in a `@MainActor` method, so the task body **inherits `@MainActor`**.
`priority:` is only a scheduling hint; it does not move the body off-main.

- `await recommendationEngine.recommendations(for:)` (line 373) *does* run
  off-main — `RecommendationEngine` is a non-isolated `Sendable struct`. The
  scoring math + DB reads are genuinely off-main and low-priority.
- But after the `await`, lines 388–390 resume on `@MainActor`: a ~95K-element
  `for` loop rebuilding `[Episode.ID: Float]`, then the `@Observable` publish
  `recommendationScoresState = .loaded(values)`, then a second `@MainActor`
  task via `kickRecommendationHydration()`.

So `.utility` governs only the scoring. The two things that hit the UI are not
gated by priority:

1. **Result-marshalling pinned to `@MainActor`** — the ~95K remarshal + publish
   + the SwiftUI list re-evaluation it drives, ×4–9 per session.
2. **Held GRDB reader connections** — `AppDB.makeConfiguration()` sets no
   `maximumReaderCount`, so `DatabasePool` uses GRDB's small default. A
   `.utility` read *holding* a connection for a ~1.6 s scan cannot be
   deprioritized off it; a user-interactive UI read just waits. QoS schedules
   CPU; it does not reclaim a held connection.

## Fix direction

- Have `recommendations(for:)` return the final `[Episode.ID: Float]` so there
  is no ~95K remarshal on the main actor — only the small `.loaded` assignment
  lands on `@MainActor`.
- Coalesce/debounce `kickRecommendationFetch`; skip when scoring inputs are
  unchanged.
- Cache the embedding matrix in memory; invalidate only on embedding writes.

The embedding cache is real design work, not transcription — `RecommendationEngine`
is a `Sendable struct` and cannot own it; needs a dedicated `actor`, incremental
invalidation, and a memory budget. See the **#296 "Implementer handoff" comment**
for the gaps the one-line fix direction glosses, plus the regression-test approach.

## Related

- [[podcast_detail_recommendation_storm]] — #293, the sibling bug: same
  architectural weakness (a SwiftUI observation triggering uncoalesced heavy
  work), different loop. Either one alone pegs the whole app.
- #298 — revert of the `c45e2908` diagnostic probes, blocked by #293 + #296.
- [[recommendation_sort_prewarming]] — recommendation behaviour a fix must preserve.
