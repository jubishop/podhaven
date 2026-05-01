# ML Recommendations

On-device ML recommendation engine for podcast episodes — infrastructure in PR #117, engine + UI on `worktree-appleMLRecommendations-UI`.

## Status

Split across two branches as of 2026-04-21:

- **PR #117 / `worktree-appleMLRecommendations`** — ratings schema + embedding pipeline + repo queries (no engine, no UI).
- **`worktree-appleMLRecommendations-UI`** — `RecommendationEngine.swift`, rating UI (PlayBarSheet, EpisodeDetailView, context menu), command-center handlers, `RecommendationEngineTests`. Depends on #117.

Plan at `.claude/plans/cozy-bouncing-shore.md`.

## Why

Users have no intelligent help choosing which episode to listen to next from their library.

## What was built (v1)

- Three-tier rating system (love/like/dislike) with `EpisodeRating` enum, CHECK constraint, rating propagated through `EpisodeFoundational` → `OnDeck` → all episode types.
- `EmbeddingService` using `NLContextualEmbedding` only (no sentence embedding fallback — waits for contextual assets to download). Text cleaning (incl. manual HTML-entity decode — `NSAttributedString` HTML import requires main thread and can't run in BG), separate title/description embedding (0.6/0.4), podcast vector itself blended as title/description 0.6/0.4 (recipe v2, PR #144 — empty descriptions now produce title-only podcast vectors instead of nil), then episode/podcast blend 0.75/0.25, unit normalization. Recipe versioned via `EmbeddingService.recipeVersion` constant folded into source hashes so tuning knobs invalidate cache.
- `RecommendationEngine` with dual positive/negative centroids, scoring (similarity 0.60, podcast affinity 0.20, freshness 0.20), Bayesian smoothing, temporal decay, missing-feature renormalization, confidence floor.
- Signals split across two parallel lists in `ScoringContextInputs`: `ratedSignals: [SignalEpisode]` (rating + ratingDate) and `partialSignals: [PartialSignal]` (coverageRatio + lastPlayedDate). Engine processes them in two loops with separate weights — the DB layer hands them over already split. (The original v1 used a single `allSignalEpisodes()` query returning a `SignalKind`-tagged list including `.finished`; superseded by the listened-coverage signal — see "In progress" below.)
- Rating UI in PlayBarSheet (own row), EpisodeDetailView, and episode context menus (library episodes only).
- `EmbeddingTask` background processing using existing `BackgroundTaskScheduler`, serial computation, prioritized ordering. `Task.checkCancellation()` per episode means BG expiry preserves partial progress; next run resumes via `episodesNeedingEmbeddings`.
- `VectorStorable` protocol for DRY vector serialization across `EpisodeEmbedding` and `PodcastEmbedding`. Protocol requires `dimension` and asserts `dimension * 4 == vector.count` on read.
- `VectorMath` uses Accelerate `vDSP` (dot, multiply, add, sumOfSquares, divide) — cheap win since it's called per-candidate in the ranker.
- `Episode.signal` and `Episode.candidate` SQL expressions defined once on `Episode` and reused across the signal/candidate fetches and `episodesNeedingEmbeddings`. (`Episode.signal` is now `rated || (playbackCoverage IS NOT NULL)` — see "In progress.")
- Repo naming follows project conventions: `podcast(_)`, `embedding(for:)`, `embeddings(for:)`, `insertEmbedding`, `allUnratedListenedEpisodes`, `allCandidateEpisodes`. (Originally also `allSignalEpisodes` and `allPodcastTags` — both removed; see "In progress" and the deferred / dropped items list.)

## Key architectural decisions

Reviewed via 3 rounds of Codex.

- Explicit ratings override implicit signals for the same episode.
- Disliked episodes excluded from positive centroid. They affect scoring three ways: (1) added to the negative centroid (subtracted from similarity in `scoreCandidate`), (2) podcast affinity via asymmetric 0.5 weight, (3) candidate filter excludes them from the candidate pool entirely.
- Candidate filter excludes on-deck, queued, finished, and explicitly rated episodes.
- `ratingDate` set to now on any change, nil on un-rate.
- `lastPlayedDate`/`listenedDuration` NOT part of OnDeck decoding (avoids observation churn).
- `rating` IS part of OnDeck decoding (needed for cross-surface sync).
- Embedding cache serializes `[Float]` as raw bytes via `VectorStorable` + `unsafe withUnsafeBytes` (not JSON).
- **Deterministic ordering, no exploration jitter (decided 2026-04-23).** Rankings are fully deterministic by (score, pubDate, id). Considered adding daily-seeded ±0.02 score jitter to shuffle near-ties across days; rejected. Real movement already comes from: users finishing episodes (new positive signals update centroids), new episodes arriving from subscribed shows (candidate pool turnover), and the coming `listenedDuration` work (more signal types). Jitter is a solution looking for a problem — revisit only if users actually report recs feel stale.
- **Reasons threshold is `value > 0.5`, not `contribution > 0.05` (decided 2026-04-23).** Each feature's value is normalized to [0, 1] with 0.5 = neutral, so a reason fires only when the feature is actively positive for this episode. The old `(weight/totalWeight) * value > 0.05` rule caught almost everything (similarity and podcast affinity always cleared it) and turned the reasons list into a set of non-differentiators. Under the new rule, `.similarToLiked` means "genuinely similar," `.podcastAffinity` means "positive history with this show," `.recentlyPublished` means "fresher than the half-life threshold." Reasons may be empty if no feature clears neutral — that's intentional; no fallback.
- **Scoring weights (as of 2026-04-23):** similarity 0.60, podcast affinity 0.20, freshness 0.20. Tag affinity and duration fit were removed (see deferred section). Freshness half-life default is 60 days, planned to become per-podcast.

## Rating-UI callsite contract (UI-branch work)

After `repo.updateRating(episodeID, rating:)`, the UI callsite must kick off a non-blocking `Task` that calls `EmbeddingService.upsertEpisodeEmbeddings(for: [episode], embedding: Container.shared.contextualEmbedding())` for the just-rated episode. This ensures the next recommendation generation has the rated episode's vector ready without waiting for the hour-plus BG task. `Repo` stays pure — embedding is NOT called inside `updateRating` itself.

**Why:** `BGProcessingTask` runs when iOS decides, which can be hours or days. "Rate an episode → recs reflect it soon" requires an on-demand embed pass at the callsite. Keeping it outside `Repo` preserves the Repo's single responsibility (DB access).

**How to apply:** When implementing rating UI actions on `worktree-appleMLRecommendations-UI`, after every `repo.updateRating` call, also spawn the single-episode embed task. Cheap (one episode = two inferences), no user-visible latency.

## In progress

### Listened-coverage signal (built 2026-04-27)

Replaces the simple `finished` heuristic with a bitmap-based partial-listen signal. Code landed in this branch; pending integration testing on device before being moved to "Shipped follow-ups."

**Schema (migration v40).** Two new columns on `episode`:
- `playbackCoverage` BLOB nullable — packed 1-bit-per-3-seconds bitmap of chunks actually heard.
- `lastPlayedDate` DATETIME nullable — timestamp of the last playback checkpoint.

No `listenedDuration` column. Coverage ratio is computed in Swift from the BLOB on engine rebuild — single source of truth, no integer-vs-bitmap consistency burden.

**`PlaybackCoverage` value type** (`PodHaven/Recommendations/PlaybackCoverage.swift`). Wraps the BLOB: `mark(startSeconds:endSeconds:)` OR-sets bits, `popcount × 3 / duration` gives the coverage ratio. ~150 bytes per hour-long episode at 3-second resolution. The 3s width aligns with the existing 3s playback checkpoint cadence so each checkpoint marks roughly one bit.

**Playback write path** (`Repo.updatePlayback` + `PodAVPlayer.savePlaybackTick`). The 3s checkpoint extends to read-modify-write the BLOB and stamp `lastPlayedDate`. Caller passes `playedFrom` (the previous-checkpoint position) so the OR-mark covers exactly the seconds elapsed since last save. Backward jumps (post-seek) leave the bitmap untouched but still bump currentTime. Pause and seek paths stay on the existing `updateCurrentTime` (no bitmap, no lastPlayedDate stamp) so they don't claim listening time the user didn't actually accrue.

**`Episode.signal` SQL:** `rated || (playbackCoverage IS NOT NULL)`. A bitmap exists only after a real playback checkpoint, so next-button finishes (no checkpoint, no bitmap) never enter the signal pool. Whether the episode is currently in progress, abandoned, or even finished is irrelevant — what matters is that real listening occurred.

**`Episode.candidate` SQL:** unchanged — `unstarted && unfinished && !rated && unqueued`. Once `currentTime > 0`, the episode is permanently out of the candidate pool. No "re-admit long-abandoned episodes" clause — decided 2026-04-27 that if a user started something they saw it, regardless of how long ago.

**Two-list signal model.** `SignalKind` was removed. Instead, `ScoringContextInputs` carries two parallel lists:

```swift
struct ScoringContextInputs {
  let ratedSignals: [SignalEpisode]   // rated only — rating + ratingDate
  let partialSignals: [PartialSignal] // bitmap-derived — coverageRatio + lastPlayedDate
  // ...
}
```

The engine processes them in two separate loops. `.finished`-as-signal was bad data (next-button polluted the positive centroid); the bitmap-derived partial is immune both to next-button (no checkpoint → no bitmap) and scrub-to-end (jumping ahead doesn't fill bits). Partial signals are positive-only; only explicit `.rating(.disliked)` contributes to the negative centroid. Listening to a little is weak interest, never aversion.

**`finishDate` column kept.** Still drives queue/UI behavior, still excludes from `Episode.candidate` (so we don't re-recommend something the user dismissed via next-button), no longer feeds the centroid on its own.

**Engine weights:**
- `lovedWeight = 1.0`
- `likedWeight = 0.6` (up from 0.5 — wider gap to `partialWeight` reinforces explicit > implicit)
- `partialWeight = 0.4` (applied as `partialWeight × coverageRatio × decay`; fully covered ≈ 0.4, half covered ≈ 0.2, 10% covered ≈ 0.04 ≈ noise)
- `finishedWeight` removed

Temporal decay (existing 180-day half-life) applies to partials via `lastPlayedDate`, same role `ratingDate` plays for ratings.

**Observation strategy.** With hundreds of signal episodes per user, per-checkpoint observation re-fetches would steal cycles even at `.utility`. So we exclude playback-path columns from the observed region and refresh on explicit triggers:

- `SignalEpisode.databaseSelection` is `id, podcastId, rating, ratingDate`. The narrow GRDB observation only fires when rating columns change.
- Both call sites — the observation in `Observatory.scoringContextInputsWithoutPartialSignals()` and the engine's debounced rebuild in `Repo.scoringContextInputs()` — share a single static builder, `Repo.scoringContextInputs(_:partialSignals:)`. The observation passes the default empty closure, so `partialSignals` is always `[]` and `playbackCoverage` / `lastPlayedDate` stay out of GRDB's tracked region; per-tick `updatePlayback` writes therefore do not wake the observation. The rebuild path passes a real `PartialSignal` fetcher.
- `RecommendationEngine` subscribes to `SharedState.$onDeck` and treats every transition (including nil → new) as a session boundary — that's the trigger that catches partial-signal staleness within a playback session. Both triggers (GRDB observation and onDeck transition) feed a single debounced rebuild that always re-reads `Repo.scoringContextInputs()`, so whichever wins the debounce sees fresh DB state at fire time.
- `prepareForForeground` already calls `engine.start()` — catches anything missed across launches.
- Pause does *not* trigger refresh — pauses-and-resumes for phone calls are routine; a pause-debounce would either flap or add staleness.

Accepted tradeoff: in a single playback session, the engine cache reflects coverage as of session start. A user who listens for an hour without finishing, changing episodes, or backgrounding sees slightly stale recs until next session boundary. Niche; revisit if reported.

**Files touched:**
- New: `Recommendations/PlaybackCoverage.swift`, `Recommendations/PartialSignal.swift`, migration `v40`, tests `PlaybackCoverageTests`, `PlaybackCoverageRepoTests`, `V40MigrationTests`.
- Modified: `Recommendations/SignalEpisode.swift` (rated-only), `Recommendations/ScoringContextInputs.swift` (two lists), `Recommendations/RecommendationEngine.swift` (weights + two-loop centroid), `Database/Models/Episode.swift` (signal SQL + `hasCoverage` + new column refs), `Database/Observatory.swift` (merged-stream `scoringContextInputs()` + `refreshScoringContext()`), `Database/Repo.swift` (`updatePlayback`, `allPartialSignals`), `Play/Utility/PodAVPlayer.swift` (`savePlaybackTick`), `Play/PlayManager.swift` (refresh triggers).

## Deferred to v2

### Per-podcast freshness half-life

The freshness curve `1 / (1 + days / halfLife)` uses a global `freshnessHalfLifeDays` (currently 60 — chosen as a default that serves the "unconfigured" case well for typical time-sensitive subscriptions; evergreen content will override). A news show has a 30-day half-life of relevance; a history podcast has 2+ years. Plan of attack: (1) schema migration adding `freshnessHalfLifeDays: Int?` nullable column on `podcast` with global fallback; (2) UI slider/numeric field in `PodcastSettingsView` with sensible presets (News 30 / Default 90 / Evergreen 365+); (3) engine reads `episode.podcast.freshnessHalfLifeDays ?? Self.freshnessHalfLifeDays`. Keep `RecommendationEngine.freshnessHalfLifeDays` as the default. Will need `episode.podcast` lookup per candidate — either batch-fetch podcasts upfront (already done for affinity) or denormalize onto episode.

### Per-podcast diversity / same-show cap

The engine sorts by score and returns `limit` results with no constraint on podcast repetition — top-N could all be from one show. Deferred 2026-04-23 after reviewing two options:

1. **Scaled hard cap** — `maxPerPodcast = ceil(limit / minDistinctPodcasts)` applied after sort, before confidence floor. Simple, predictable, fits the current sort → filter → prefix pipeline. Downside: can surprise users ("why did my 4.0 get dropped for a 3.2?").
2. **Soft demotion / greedy MMR** — multiply effective score by `repeatPodcastDemotion ^ prior_count` when selecting next pick. Scales naturally for any `limit`, more elegant, but requires a greedy re-selection loop that replaces the straight sort. A close-to-best candidate from a new show beats a just-slightly-better one from an already-picked show.

Revisit when there's an actual suggestions UI consuming this — design choice will feel different once it's visible. Start with option 1 for simplicity; fall back to option 2 only if score-drop surprise becomes a real complaint.

### Other deferred / dropped items

- Command Center like/dislike integration (dropped — low value).
- Suggestions UI (no consumer of recommendations yet).
- `NLEmbedding.sentenceEmbedding` fallback (removed — just wait for contextual assets).
- **Duration-fit feature.** Removed 2026-04-23. Reason: weak predictor (humans' preferred episode length varies by listening context — commute vs workout vs wind-down — so a single median-of-positives isn't meaningfully "fit"); the `min/max` symmetric ratio formula is decent but the signal itself doesn't justify the complexity. Redistributed the freed 10% to similarity (+5) and freshness (+5). If we ever want duration filtering, make it a hard filter ("hide episodes longer than X min") user-controlled, not a scoring feature.
- **Tag affinity feature.** Removed 2026-04-23 and its 15% weight folded into `similarityWeight` (0.40 → 0.55). Reasons: (a) user-applied tags are a derivative of podcast affinity (tags live at the podcast level, so episodes of already-liked-tagged shows double-counted at 20% + 15% = 35% for "you already like this show"); (b) the formula `overlap / likedTags.count` didn't penalize over-tagged podcasts (no Jaccard normalization); (c) semantic similarity at 40%+ already captures topical overlap between shows organically — e.g. another history podcast's embedding is already close to a loved history podcast's embedding. If we revisit, the better shape is Jaccard (`overlap / union`) and a much smaller weight (~5%), gated on the user having tagged ≥N podcasts so non-taggers don't pay for a silent-zero feature. Repo APIs removed with the feature: `allPodcastTags()` on `Databasing` / `Repo` / `FakeRepo`. `PodcastTag` model retained (used by tagging UI).

## Shipped follow-ups (post-v1)

### `ScoringContext` caching via `Observatory` — shipped 2026-04-24

`RecommendationEngine` caches the centroid+affinity result in `ThreadSafe<ScoringContext?>(nil)`. `Observatory.scoringContextInputs()` emits a `ScoringContextInputs` snapshot — small Sendable+Equatable struct (`signals`, `signalEmbeddings`, `hasAnyEmbeddings`) so `removeDuplicates()` works without forcing Equatable on `Episode`/`UnsavedEpisode`. Engine exposes a sync `func start()` matching the codebase convention (`startOnce.run { startObservingScoringContext() }`, mirroring `StateManager`/`CacheManager`/`WidgetSnapshotWriter`). The observation Task runs at `.utility` via `Container.shared.taskPriority()` so tests don't get starved by priority inheritance. **Public scoring methods don't await `start()`** — `recommendations(for:)` / `topRecommendations()` just read whatever the cache currently holds and return empty when it's nil. Lifecycle owners are responsible for hydration: AppLauncher calls `recommendationEngine.start()` during `prepareForForeground` so the cache is hot by the time any UI surface asks; tests call `engine.start()` after seeding their fixture and (when expecting non-empty results) poll `engine.topRecommendations()` via `Wait.forValue` until the cache lands. **No debounce** — `buildContext` is single-digit ms, GRDB's `removeDuplicates()` collapses no-op transitions, real bursts only happen during background embedding writes when no UI is consuming, and a debounce window adds a "cache is staler than DB" reasoning burden that doesn't earn its complexity.

Files: `PodHaven/Recommendations/ScoringContextInputs.swift`, `Observatory.scoringContextInputs()`, `RecommendationEngine.start()`. Tests: `ObservatoryScoringContextInputsTests` (initial empty, projection, hasAnyEmbeddings semantics, re-emit on rating, re-emit on embedding, ignores irrelevant column changes) — engine end-to-end behavior covered by the existing `RecommendationEngineTests` with two helpers (`startAndWaitForRecs`, `startAndWaitForScores`) that capture engine into a local before the polling closure to dodge the test class's non-Sendable `self`.

Rejected alternatives: TTL cache, waiter-dict pattern (cache state ballooned to context+initialized+waiters), AsyncOnce-gated `start() async` (let public methods stay non-blocking instead), denormalized score column, bundling scores into Repo queries.

### Dislike bleed mitigation — addressed 2026-04-23

Chose mitigation option 2 (asymmetric weights): dislikes contribute at `dislikedAffinityWeight = 0.5` while positives stay at 1.0. Option 1 (drop negatives entirely) was considered cleaner but loses real show-level preference signal; asymmetric keeps the signal at half strength so repeated dislikes still register as show aversion without one bad episode tanking an otherwise-loved show.

## Known v1 design limitations (reviewed 2026-04-22, not blocking)

- **English-only embeddings.** `NLContextualEmbedding(language: .english)` is pinned at construction. Non-English podcast titles/descriptions get vectors from an English-tuned model — noisy but not meaningless. Revisit if a user reports poor recs on non-English content; fix would be per-text or per-podcast language detection via `NLLanguageRecognizer`, carrying the cost of multiple model loads.
- **Known item #14 (unresolved):** `ContextualEmbedding.requestAndLoadAssetsIfNeeded` re-resolves itself via `Container.shared.contextualEmbedding()` inside a `@Sendable` completion handler instead of capturing `self`. Clean `[weak self]` would require making `ContextualEmbedding: Sendable`, which chains through `any Embeddable` → `NLContextualEmbedding` (Apple class, not known Sendable). Accepted as-is; the re-resolve is safe because the container uses `.scope(.cached)`.
