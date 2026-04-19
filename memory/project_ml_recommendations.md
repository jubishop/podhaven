---
name: ML Recommendations Feature
description: On-device ML recommendation engine for podcast episodes — implemented in PR #117, using NLContextualEmbedding, dual centroids, podcast blending, and tag-based signals
type: project
---

Major feature: on-device ML episode recommendation system. PR #117 (branch `worktree-appleMLRecommendations`). Plan at `.claude/plans/cozy-bouncing-shore.md`.

**Why:** Users have no intelligent help choosing which episode to listen to next from their library.

**How to apply:** When working on any recommendation/rating/embedding code, reference the plan and the existing implementation in `PodHaven/Recommendations/`.

**What was built (v1):**
- Three-tier rating system (love/like/dislike) with `EpisodeRating` enum, CHECK constraint, rating propagated through `EpisodeFoundational` → `OnDeck` → all episode types
- `EmbeddingService` using `NLContextualEmbedding` only (no sentence embedding fallback — waits for contextual assets to download). Text cleaning, separate title/description embedding, podcast description blending (60/40), unit normalization.
- `RecommendationEngine` with dual positive/negative centroids, 5-feature scoring (similarity 0.40, podcast affinity 0.20, tag affinity 0.15, freshness 0.15, duration fit 0.10), Bayesian smoothing, temporal decay, missing-feature renormalization, confidence floor
- Rating UI in PlayBarSheet (own row), EpisodeDetailView, and episode context menus (library episodes only)
- `EmbeddingTask` background processing using existing `BackgroundTaskScheduler`, serial computation, prioritized ordering
- `VectorStorable` protocol for DRY vector serialization across `EpisodeEmbedding` and `PodcastEmbedding`
- Repo naming follows project conventions: `podcast(_)`, `embedding(for:)`, `embeddings(for:)`, `insertEmbedding`, `allSignalEpisodes`, `allCandidateEpisodes`, `allPodcastTags`

**What was deferred to v2:**
- `listenedDuration` tracking (richer implicit signals)
- Command Center like/dislike integration (dropped — low value)
- Suggestions UI (no consumer of recommendations yet)
- `NLEmbedding.sentenceEmbedding` fallback (removed — just wait for contextual assets)

**Key architectural decisions (extensively reviewed via 3 rounds of Codex):**
- Explicit ratings override implicit signals for the same episode
- Disliked episodes excluded from positive centroid, affect scoring via podcast affinity + candidate filter
- Candidate filter excludes on-deck, queued, finished, and explicitly rated episodes
- `ratingDate` set to now on any change, nil on un-rate
- `lastPlayedDate`/`listenedDuration` NOT part of OnDeck decoding (avoids observation churn)
- `rating` IS part of OnDeck decoding (needed for cross-surface sync)
- Embedding cache uses JSON-encoded `[Float]` via `VectorStorable` protocol (avoids `unsafe` constructs)
- One disabled test (`sourceHashInvalidation`) needs investigation for podcast blending interaction in test environment
