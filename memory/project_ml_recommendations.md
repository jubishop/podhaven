---
name: ML Recommendations Feature
description: On-device ML recommendation engine for podcast episodes — infrastructure in PR #117, engine + UI on `worktree-appleMLRecommendations-UI`
type: project
originSessionId: 50c1dd09-f49e-4dbb-93ed-9e1439447c2c
---
Major feature: on-device ML episode recommendation system. Split across two branches as of 2026-04-21:
- **PR #117 / `worktree-appleMLRecommendations`** — ratings schema + embedding pipeline + repo queries (no engine, no UI).
- **`worktree-appleMLRecommendations-UI`** — `RecommendationEngine.swift`, rating UI (PlayBarSheet, EpisodeDetailView, context menu), command-center handlers, `RecommendationEngineTests`. Depends on #117.

Plan at `.claude/plans/cozy-bouncing-shore.md`.

**Why:** Users have no intelligent help choosing which episode to listen to next from their library.

**How to apply:** When working on any recommendation/rating/embedding code, reference the plan and the existing implementation in `PodHaven/Recommendations/`.

**What was built (v1):**
- Three-tier rating system (love/like/dislike) with `EpisodeRating` enum, CHECK constraint, rating propagated through `EpisodeFoundational` → `OnDeck` → all episode types
- `EmbeddingService` using `NLContextualEmbedding` only (no sentence embedding fallback — waits for contextual assets to download). Text cleaning (incl. manual HTML-entity decode — NSAttributedString HTML import requires main thread and can't run in BG), separate title/description embedding, podcast description blending (0.75/0.25 post-review), unit normalization. Recipe versioned via `EmbeddingService.recipeVersion` constant folded into source hashes so tuning knobs invalidate cache.
- `RecommendationEngine` with dual positive/negative centroids, 5-feature scoring (similarity 0.40, podcast affinity 0.20, tag affinity 0.15, freshness 0.15, duration fit 0.10), Bayesian smoothing, temporal decay, missing-feature renormalization, confidence floor
- `allSignalEpisodes()` returns `[SignalEpisode]` where each carries a `SignalKind` (`.rating(EpisodeRating)` or `.finished`). Engine pattern-matches on kind for positive/negative centroid split — DB layer does not pre-split.
- Rating UI in PlayBarSheet (own row), EpisodeDetailView, and episode context menus (library episodes only)
- `EmbeddingTask` background processing using existing `BackgroundTaskScheduler`, serial computation, prioritized ordering. `Task.checkCancellation()` per episode means BG expiry preserves partial progress; next run resumes via `episodesNeedingEmbeddings`.
- `VectorStorable` protocol for DRY vector serialization across `EpisodeEmbedding` and `PodcastEmbedding`. Protocol requires `dimension` and asserts `dimension * 4 == vector.count` on read.
- `VectorMath` uses Accelerate `vDSP` (dot, multiply, add, sumOfSquares, divide) — cheap win since it's called per-candidate in the ranker.
- `Episode.signal` and `Episode.candidate` SQL expressions defined once on `Episode` and reused across `allSignalEpisodes`, `allCandidateEpisodes`, `episodesNeedingEmbeddings`.
- Repo naming follows project conventions: `podcast(_)`, `embedding(for:)`, `embeddings(for:)`, `insertEmbedding`, `allSignalEpisodes`, `allCandidateEpisodes`, `allPodcastTags`

**What was deferred to v2:**
- **`listenedDuration` + `lastPlayedDate` tracking.** This is a cross-cutting change, not a single column add. Touch points, in roughly the order you'd implement them:
  1. **Schema migration** — add `listenedDuration` (CMTime/integer seconds) and `lastPlayedDate` (datetime) columns on `episode`, with triggers if we want them auto-maintained.
  2. **Playback write path** — update `listenedDuration` as the user plays. Must be *cumulative distinct* playback (re-listening the same segment shouldn't double-count), not just `currentTime`. Needs a design decision: track via interval math in `PlayManager`, or store a coverage bitmap per episode.
  3. **`Episode.signal` SQL expression** — expand from `rated || finished` to include a partial-listening threshold (e.g. `listenedDuration / duration >= 0.7`). DB-side filter must stay in sync with Swift-side classification.
  4. **`Episode.candidate` SQL expression** — currently `unstarted && unfinished && !rated && unqueued`. This permanently excludes any episode with `currentTime > 0`. v2 needs to re-admit long-abandoned ones: something like `(unstarted || (lowListenedRatio && lastPlayedOlderThan)) && unfinished && !rated && unqueued`.
  5. **`SignalKind` enum** — add cases for partial-listening signals, e.g. `.mostlyListened(ratio: Double)` (weak positive) and `.sampled(ratio: Double)` (weak negative). Associated values vs. bucketed cases is a design call.
  6. **`SignalEpisode.init(from:)`** — today it's total (every rated-or-finished episode is a signal). With thresholds added, it may need to become failable (`init?(from:)`) OR the SQL predicate must pre-filter so the init only runs on guaranteed signals. Keep explicit-rating-wins precedence: rating → finished → mostlyListened → sampled.
  7. **`RecommendationEngine` scoring (UI branch)** — decide where the new SignalKind cases go: `.mostlyListened` as positive-centroid at lower weight? `.sampled` as negative-centroid or ignored? Real engine change, not just plumbing.
- Command Center like/dislike integration (dropped — low value)
- Suggestions UI (no consumer of recommendations yet)
- `NLEmbedding.sentenceEmbedding` fallback (removed — just wait for contextual assets)

**Known v1 design limitations (reviewed 2026-04-22, not blocking):**
- **English-only embeddings.** `NLContextualEmbedding(language: .english)` is pinned at construction. Non-English podcast titles/descriptions get vectors from an English-tuned model — noisy but not meaningless. Revisit if a user reports poor recs on non-English content; fix would be per-text or per-podcast language detection via `NLLanguageRecognizer`, carrying the cost of multiple model loads.
- **Dislike bleed through podcast affinity.** Podcast affinity is `bayesianSmooth(positives, negatives)` where BOTH positive and negative signals from a show contribute. Disliking one episode from an otherwise-loved show penalizes every other episode from that show via the affinity feature. Bayesian smoothing softens but doesn't eliminate this. **Mitigation ideas when we next touch the engine (in priority order):** (1) Drop negatives from podcast affinity entirely — let the negative centroid handle show-level dislike organically via semantic similarity. (2) Asymmetric weights — dislikes contribute to affinity at e.g. half the weight of positives. (3) Raise the Bayesian smoothing prior so one dislike matters less. Also, drop a `// TODO:` in `RecommendationEngine.swift` near the podcast-affinity calculation on the UI branch when rebasing.

**Key architectural decisions (extensively reviewed via 3 rounds of Codex):**
- Explicit ratings override implicit signals for the same episode
- Disliked episodes excluded from positive centroid, affect scoring via podcast affinity + candidate filter
- Candidate filter excludes on-deck, queued, finished, and explicitly rated episodes
- `ratingDate` set to now on any change, nil on un-rate
- `lastPlayedDate`/`listenedDuration` NOT part of OnDeck decoding (avoids observation churn)
- `rating` IS part of OnDeck decoding (needed for cross-surface sync)
- Embedding cache serializes `[Float]` as raw bytes via `VectorStorable` + `unsafe withUnsafeBytes` (not JSON; prior memory was wrong)
- `sourceHashInvalidation` test is currently enabled in `EmbeddingServiceTests.swift` (previously thought disabled)

**Rating-UI callsite contract (UI-branch work):**
After `repo.updateRating(episodeID, rating:)`, the UI callsite must kick off a non-blocking `Task` that calls `EmbeddingService.upsertEpisodeEmbeddings(for: [episode], embedding: Container.shared.contextualEmbedding())` for the just-rated episode. This ensures the next recommendation generation has the rated episode's vector ready without waiting for the hour-plus BG task. `Repo` stays pure — embedding is NOT called inside `updateRating` itself.

**Why:** `BGProcessingTask` runs when iOS decides, which can be hours or days. "Rate an episode → recs reflect it soon" requires an on-demand embed pass at the callsite. Keeping it outside `Repo` preserves the Repo's single responsibility (DB access).

**How to apply:** When implementing rating UI actions on `worktree-appleMLRecommendations-UI`, after every `repo.updateRating` call, also spawn the single-episode embed task. Cheap (one episode = two inferences), no user-visible latency.

**Known item #14 (unresolved):** `ContextualEmbedding.requestAndLoadAssetsIfNeeded` re-resolves itself via `Container.shared.contextualEmbedding()` inside a `@Sendable` completion handler instead of capturing `self`. Clean `[weak self]` would require making `ContextualEmbedding: Sendable`, which chains through `any Embeddable` → `NLContextualEmbedding` (Apple class, not known Sendable). Accepted as-is; the re-resolve is safe because the container uses `.scope(.cached)`.
