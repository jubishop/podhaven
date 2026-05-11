# Search Recommendations

Rank the episodes of podcasts returned from a search by the existing ML recommendation engine, surfacing a "top recommended episodes from these results" list as a discovery tool. Design captured 2026-05-11; planning only.

## Context

The recommendation engine (`PodHaven/Recommendations/RecommendationEngine.swift`) is already decoupled enough to score arbitrary episodes — `recommendations(for: [Episode])` at line 111 takes any episode set and returns `[Episode.ID: RecommendationScore]` against the user's cached centroid + affinity context. Today it's only consumed by UpNext, which feeds it episodes already in the local DB.

Search (`PodHaven/Views/Search/Models/SearchViewModel.swift:32`) produces `PowerList<PodcastWithEpisodeMetadata<ListedPodcast>>` — podcast-level results with lightweight episode metadata. The episodes themselves don't live in the local DB unless the user subscribes. This initiative bridges the gap: fetch the RSS feeds of the top search-result podcasts, embed their recent episodes on the fly, score them through the engine, and present the result as a standard `EpisodesListView` reached via a banner above the search-result grid.

The intended outcome: every time the search returns results, a banner appears above the grid showing a running count ("Top 14 episodes from these results →"). Tapping it pushes an `EpisodesListView` titled with the original search string, sorted descending by recommendation score, that fills in episodes as background scoring completes.

### Why content-similarity-only scoring

The new engine entry point this initiative adds scores by similarity to the user's centroid alone — no podcast affinity, no freshness gate. Both of those terms exist for a different question ("what should I play next from my subscriptions?") and would distort a discovery surface:

- **Affinity** would heavily bias the list toward podcasts the user already rates highly — irrelevant for unsubscribed podcasts (no rating history) and counter-productive for subscribed ones (the discovery list would become "your top subscribed podcasts again").
- **Freshness** is multiplicative (`RecommendationEngine.swift:531`), so a 2018 episode of a perfectly-matched podcast would be penalized into oblivion. For a search-driven view, the user's lens is content match, not recency.

### Why subscribed podcasts are still excluded

Stripping affinity from the scoring isn't enough on its own. The user's centroid is built from episodes they've liked, whose titles and descriptions overwhelmingly come from podcasts they're already subscribed to — so **podcast affinity leaks through the centroid itself**. A pure content-similarity score will still rank subscribed-podcast episodes highly on shape alone, and the discovery list would collapse back to "your subscribed podcasts again" through the side door.

On top of that, candidate episodes from subscribed podcasts (i.e. ones that pass `Episode.candidate && id != onDeckID`) are exactly what UpNext already surfaces. Including them in a search-discovery list is duplicative with an existing surface that does the same job with the full scoring signal (affinity + freshness included).

So the collector **excludes subscribed podcasts entirely**. Every podcast it processes is unsubscribed: RSS fetch → parse → embed → score. There is no cheap path.

---

## Architecture

### 1. Engine entry point — `PodHaven/Recommendations/RecommendationEngine.swift`

New public method, parallel to `recommendations(for:)`:

```swift
// Score discovery candidates by similarity alone. Used when the caller
// already has the embeddings in hand and there is no meaningful podcast
// affinity or freshness signal — search-driven discovery, where the
// user's lens is content match, not recency, and affinity would just
// re-rank by "podcasts you already like." Returns scores keyed by the
// caller-supplied opaque ID. Returns empty if `start()` hasn't yet
// hydrated the cache.
func discoveryScores<ID: Hashable & Sendable>(
  for candidates: [(id: ID, embedding: [Float])]
) async -> [ID: RecommendationScore]
```

The collector's current use keys on a synthetic `(feedURL, guid)` composite, since unsubscribed-podcast episodes don't have an `Episode.ID`. The generic ID parameter keeps the entry point honest as a general-purpose primitive — future discovery callers (e.g. an "explore" tab seeded from elsewhere) can plug in their own key type without forcing the engine to know about RSS shapes. Internally the method cosines each candidate against the cached `positiveCentroid` (and subtracts against `negativeCentroid` if present) using the same primitive that `scoreCandidate` already calls, but skips the affinity blend and freshness multiply. Returns `RecommendationScore` with `reasons: [.similarToLiked]` only — the other two reason variants don't apply.

This is additive — no changes to `recommendations(for:)` or `topRecommendations(limit:)`. Both keep their current contract for UpNext.

### 2. Banner placement — `PodHaven/Views/Search/Views/`

The banner sits above the existing search-result grid, between the search field and the `PowerList` rendering. It renders only when:

- The cached `ScoringContext` exists (engine `start()` has hydrated). Cold-start users with no rated episodes get no banner — there's nothing to score against.
- The collector has at least one scored episode buffered.

Label format: `"Top \(count) from \"\(query)\" →"`. Tapping pushes the discovery list onto the search tab's navigation stack.

### 3. The collector — `PodHaven/Recommendations/SearchRecommendationCollector.swift` (new)

A `@MainActor` `@Observable` class owned by `SearchViewModel`. One instance per active search query; the previous instance is cancelled when the query changes.

Responsibilities:

- Observe `SearchViewModel.podcastList`. When new search results arrive, take the first **P** by search ranking, **then drop any the user is subscribed to** (see "Why subscribed podcasts are still excluded" above), then enqueue the survivors that aren't already in the seen-set. The cap happens *before* the subscription filter — we don't walk deeper into the result list to backfill the discovery budget, since the 30th-ranked search result has no business being shown as a "top pick."
- Take the most recent **E** episodes per enqueued podcast (by `pubDate` desc). Starting values: `P = 25`, `E = 10`. Both are **tunable** — they trade discovery surface area against RSS load + embedding cost, and the right values will fall out of measurement once the feature is wired up. Captured here as constants near the collector so they're easy to find and adjust. Note that with subscribed podcasts excluded, every enqueued podcast pays the full RSS+embed cost, so P caps the network/CPU load directly.
- For each enqueued podcast, fan out a child Task at `taskPriority(.utility)`:
  1. Fetch + parse RSS via `PodcastFeed.parse(downloadTask.downloadFinished())` (same path `RefreshManager.refreshSeries` uses at `RefreshManager.swift:97`).
  2. Take the E most recent episodes from the parsed feed.
  3. Apply the candidate filter. Most episodes from these podcasts won't have a DB row at all (so the filter is a no-op for them), but the user *might* have interacted with one previously — played, queued, or rated an episode from a podcast they never subscribed to. Resolve via one batch query: `SELECT … FROM episode WHERE guid IN (…) OR mediaURL IN (…)` keyed by the RSS episodes' natural keys. For each match, apply `Episode.candidate && id != onDeckID` (`Episode.swift:248`) — which excludes finished, queued, started, rated, and onDeck episodes — and drop the failures. Episodes with no matching row pass through.
  4. For surviving episodes, call `EmbeddingService.embed(episode:)` to produce a vector. Skip any episode that fails to embed (e.g. NLContextualEmbedding asset unavailable for the detected language).
  5. Pass the batch to `engine.discoveryScores(for:)`.
- Merge scored episodes into the published `episodes` array, keyed by `(feedURL, guid)`. Re-sort on every insert. UI observes and re-renders silently.
- Track a minimum-score floor identical to UpNext (`minimumScoreThreshold`, `RecommendationEngine.swift:185`) so the list isn't polluted by low-similarity matches.

Cancellation lifecycle:

- The collector holds its root `TaskGroup` (or stored child Tasks). On `deinit`, on query change, and when the user navigates out of the search tab, all in-flight Tasks are cancelled. URLSession requests cancel cleanly through `DownloadManager`; embedding work checks `Task.isCancelled` between episodes.
- The published `episodes` array is the collector's source of truth — it persists for the collector's lifetime (i.e. for as long as the query is unchanged and search is on-screen) and is dropped when the collector is.

### 4. Discovery list view

A new `EpisodeListable` source backed by the collector's `episodes` array. The existing `EpisodesListView` already renders any `EpisodeListable` collection, so the integration is:

- A bridge type that wraps `[ListedEpisode]` — every entry is the `UnsavedPodcastEpisode` case (carrying the RSS-derived episode + the collector's `RecommendationScore` for sorting), since the collector only surfaces episodes from unsubscribed podcasts.
- The view's navigation title is the original search query string. Subtitle (if the existing view supports one) shows "Recommended for you" or similar.
- Sort is fixed: score desc, then pubDate desc, then guid. The standard sort toolbar is hidden here — the whole point of this view is "ranked by recommendation," and exposing the sort menu would invite a confusing "what does the engine think of these in pubDate order?" reading.
- Tapping an episode opens the existing episode detail view. **Verify** that the detail-view + play path handles `UnsavedPodcastEpisode` end-to-end without subscribing (this should already work — Search already lets users play episodes from unsubscribed podcasts — but worth confirming as part of implementation).

### 5. Search VM integration — `PodHaven/Views/Search/Models/SearchViewModel.swift`

- Hold an optional `collector: SearchRecommendationCollector?`.
- When the query changes (existing branches around `SearchViewModel.swift:404`), tear down the old collector and instantiate a new one bound to `podcastList`.
- Expose `collector?.episodes.count` and `collector?.query` so the banner view can render its label without reaching into the collector directly.

---

## Scoring nuances

- **Centroid availability.** `discoveryScores(for:)` returns empty when the engine cache is cold. The banner stays hidden in that case — there's no graceful "partial discovery" mode worth building before the user has any liked/loved episodes. Cold-start cohort is small.
- **Negative centroid.** If the user has disliked episodes, the negative centroid is subtracted as today. This is desirable for discovery — content the user has actively rejected shouldn't bubble up via search.
- **English-only embeddings.** `NLContextualEmbedding` is English in this app's recipe (`EmbeddingService.swift:13–25`). Episodes whose title/description can't be embedded are silently skipped. Acceptable for v1; non-English handling is a separate concern.
- **No freshness penalty.** Stated explicitly because it differs from UpNext. A 2018 episode of a newly-discovered podcast that perfectly matches the user's taste should rank above a 2026 episode that doesn't.

## Cancellation & cost ceiling

At the starting `P = 25`, `E = 10` caps, every enqueued podcast is unsubscribed, so every podcast costs one RSS fetch (200ms–2s, parallel) + E embeddings (~10ms each on-device). Typical case is **3–8s wall clock** at utility priority, RSS-bound. If a search returns mostly subscribed podcasts (e.g. the user searches a term that matches several of their subscriptions), the collector fills its P budget from fewer results and may end up with a shorter list — acceptable, and arguably correct: those subscribed matches are UpNext's job.

Cancellation matters because users tab out of search quickly. Per the lifecycle decision, leaving the search screen cancels every in-flight Task — no zombie network requests or embeddings continuing after the user has moved on.

---

## Deferred: persisted embedding cache for discovery

Not part of v1. Captured here so the option exists when/if the "embed-on-every-search" approach proves too slow or too power-hungry. **None of what follows applies to v1** — v1 doesn't persist anything new. Subscribed-podcast embeddings already live in `episodeEmbedding` and the existing versioning there handles itself; unsubscribed-podcast embeddings are computed and discarded inside the collector. The recipe-version / eviction concerns below only become real once we decide to *keep* unsubscribed-podcast embeddings on disk between searches.

### Why we might want it

Embedding work is repeated every time the same search runs. A user who searches "naval ravikant" twice will pay the full embedding cost for that podcast's episodes twice. With a persisted cache, the second search becomes nearly instant (RSS-fetch-bounded only — and even RSS responses get URLSession-level conditional caching via `Last-Modified` / `ETag`).

### Why we might not

- **Storage growth.** ~512 floats × 4 bytes = 2KB per embedding. P podcasts × E episodes × N distinct searches/day adds up to MBs/week of vectors the user may never see again.
- **Cache invalidation cost.** The embedding recipe is versioned (`recipeVersion = 2`, `EmbeddingService.swift:15`). If we tune the recipe, every cached vector from the old recipe is wrong — they have to be discarded and recomputed. The cache earns its keep across long stretches of stable recipe, but every recipe bump wipes it.
- **Code complexity.** v1 has no persistence layer for discovery candidates at all. Adding one means a new column, a new eviction policy, a new code path that has to stay correct under recipe-version changes, and a new test surface.

### Proposed shape (if/when we revisit)

- Reuse the existing `episodeEmbedding` table rather than introducing a new one. Add a `provenance` column: `.subscribed | .discovery`. The hourly `EmbeddingProcessor` ignores `.discovery` rows; the collector writes and reads `.discovery` rows only.
- Key on `(feedURL, guid)` since unsubscribed-podcast episodes have no `Episode.ID`. This means either a synthetic ID scheme or a parallel table — preferable to back-allocating real `Episode.ID`s for episodes that aren't in the local model.
- **Eviction policy.** Time-based (`creationDate < now - 30d`) plus a hard cap on row count. When the cap is hit, evict the **least-recently-used** rows first — i.e. the ones whose `lastAccessedDate` is oldest. ("LRU" is the common shorthand: Least Recently Used. The rule is "if the cache is full, throw out whatever you haven't touched in the longest time," on the theory that recently-used entries are likeliest to be used again soon.) Eviction runs as part of the existing periodic embedding maintenance task; the collector updates `lastAccessedDate` on every read.
- **Recipe-version invalidation.** Each row already carries `embeddingRevision`. On read, `.discovery` rows whose revision doesn't match the current recipe are dropped. On a recipe bump this empties the discovery cache over time; the collector falls back to recomputing.
- Open: do we also want to cache the parsed `PodcastFeed` itself (not just the embeddings)? Probably not — URLSession's HTTP cache already handles that layer well enough, and adding a second cache for the same data is rarely worth the complexity.

A first pass would measure: how much CPU/battery does v1 actually use across a realistic search session, and how often does the same search recur within the eviction window? If both numbers are low, this stays deferred indefinitely.

---

## Risks & open questions

These are the things that aren't quite settled by the design above — surface them during implementation rather than chasing them in this doc.

- **Episode actions from an unsubscribed podcast.** When a discovery-list episode is from an unsubscribed podcast, tapping it produces an `UnsavedPodcastEpisode` instead of a DB-backed `ListablePodcastEpisode`. Search today lets you play those, but it's not obvious every downstream action (queue, like/dislike, rate, detail view, share) is wired up for the unsaved case. Worth walking each one through end-to-end during implementation. If something *does* require a real DB row, decide whether to silently materialize one, trigger the subscribe flow, or disable that action in this surface.
- **Does cancelling the collector actually cancel its RSS downloads?** A user typing quickly triggers a new collector per debounced keystroke, each one cancelling its predecessor. If `DownloadManager` keeps the URLSession task alive past the cancel, then re-issuing the same feed URL in the new collector might return the cancelled task's result instead of starting a fresh fetch. Verify cancellation propagates all the way down to the URLSession task, not just to the Swift `Task` wrapper.
- **Late-arriving banner causes a layout jump.** Search results render the moment the iTunes search returns. The banner can't render until the collector has at least one scored episode, which is 1–3 seconds later in the typical case. The result is the search grid laying out, then the banner popping in above it and shifting everything down. Acceptable, or worth a stub banner ("Finding top picks…") that holds the space from the start? UI-pass decision.

## Non-goals

- Changing the underlying recommendation algorithm. This initiative is a new *surface* for the existing engine, not a tuning pass on similarity weights, freshness, or affinity.
- Surfacing search recommendations anywhere other than the search tab. No notification, no home screen widget, no UpNext integration.
- Cross-search ranking. Each search query gets its own collector and its own ranking — we don't accumulate a global "best discovery candidates" pool across searches.
- Persistent results. The discovery list is recomputed every time the search runs. Same search tomorrow re-fetches RSS and re-embeds (modulo the deferred caching above).
