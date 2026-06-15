---
name: search-recommendation-embedding-perf
description: Search "top picks" latency is bound by the serialized embedding actor, not RSS fan-out; the podcast-context vector is computed once per feed.
type: reference
---

# Search recommendation "top picks" latency

Search/trending "top picks" (`SearchRecommendationCollector` → `SearchPipelineRunner`)
ranks external podcast episodes by content similarity. Per feed the pipeline is
fetch → parse → filter → embed → score.

The latency floor is the **embed** stage, not the network. Every
`ContextualEmbedding.vector(for:)` runs on a single actor (`ContextualEmbedding`
is an `actor`), so all concurrent feed pipelines serialize through it. Scoring
(`RecommendationEngine.similarityScores`) is `@concurrent` + vDSP and cheap; RSS
fetch fans out at `SearchRecommendationCollector.rssConcurrency`.

Consequences:

- **Raising RSS concurrency does not speed this up** past first paint — feeds
  just queue behind the one embedder. The lever is reducing embedding work or
  parallelizing the model, not fetching faster.
- Each episode needs 2 `vector(for:)` calls (title + description); the
  podcast-context vector is another 2 and is **identical for every episode of a
  feed**. `SearchPipelineRunner` computes it once per feed via
  `EmbeddingService.podcastContextVector` and threads it into
  `episodeEmbeddingVector`, instead of the old per-episode `embeddingVector` that
  recomputed it each time (roughly halves the embed calls per feed). The
  saved-side path (`EmbeddingService.upsertEpisodeEmbeddings`) already de-dups
  via its `podcastVectorCache`.

Measuring: `SearchPipelineRunner` emits a `perf:` debug line per feed (subsystem
`SearchView.recommendations`) with fetch/parse/filter/embed/score durations and
counts. Use it to confirm the network-vs-embed split before further work.

Next lever if still slow (deferred pending measurement): a small pool of
`NLContextualEmbedding` instances so embedding fans out across cores/ANE. Apple
does not document single-instance `NLContextualEmbedding` as thread-safe, so a
pool (each instance loads model weights → memory cost) is safer than concurrent
calls on one instance. See `docs/initiatives/search-recommendations.md`
("Throttle RSS and embedding separately").
