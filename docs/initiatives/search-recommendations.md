# Search Recommendations

Rank the episodes of podcasts returned from a search or a trending-category chip by the existing ML recommendation engine, surfacing a "top recommended episodes from these results" list as a discovery tool. Design captured 2026-05-11; planning only.

## Context

The recommendation engine (`PodHaven/Recommendations/RecommendationEngine.swift`) is already decoupled enough to score arbitrary episodes — `recommendations(for: [Episode])` at line 111 takes any episode set and returns `[Episode.ID: RecommendationScore]` against the user's cached centroid + affinity context. Today it's only consumed by UpNext, which feeds it episodes already in the local DB.

The search tab has two primary podcast-list surfaces that share the same rendering:

- **Typed search results** — `SearchViewModel.searchResults` (`PodHaven/Views/Search/Models/SearchViewModel.swift:207`), populated from the iTunes search API when the user types a query.
- **Trending categories** — `SearchViewModel.currentTrendingSection.results`, populated from `iTunesService.topPodcasts(genreID:limit: 48)` (`SearchViewModel.swift:307`). One chip per genre — "Top" (no `genreID`) plus 17 categories: Arts, Business, Comedy, Education, Government, Health, History, Kids, Leisure, Music, News, Science, Society & Culture, Sports, Technology, True Crime, TV & Film.

Both surfaces yield `PodcastWithEpisodeMetadata<ListedPodcast>` — podcast-level results with lightweight episode metadata. The episodes themselves don't live in the local DB unless the user subscribes. This initiative bridges the gap: fetch the RSS feeds of the top podcasts from whichever surface is active, embed their recent episodes on the fly, score them through the engine, and present the result as a standard `EpisodesListView` reached via a banner above the grid.

The intended outcome: any time a podcast-list surface in the search tab has results, a banner appears above the grid showing a running count. For typed search: `"Top 14 from \"naval ravikant\" →"`. For trending: `"Top 14 from Technology →"` (or `"Top 14 picks →"` for the unbranded "Top" chip). Tapping pushes an `EpisodesListView` titled with the originating query-or-category, sorted descending by recommendation score, that fills in episodes as background scoring completes.

### Why content-similarity-only scoring

The new engine entry point this initiative adds scores by similarity to the user's centroid alone — no podcast affinity, no freshness gate. Both of those terms exist for a different question ("what should I play next from my subscriptions?") and would distort a discovery surface:

- **Affinity** would heavily bias the list toward podcasts the user already rates highly — irrelevant for unsubscribed podcasts (no rating history) and counter-productive for subscribed ones (the discovery list would become "your top subscribed podcasts again").
- **Freshness** is multiplicative (`RecommendationEngine.swift:531`), so a 2018 episode of a perfectly-matched podcast would be penalized into oblivion. For a search-driven view, the user's lens is content match, not recency.

### Why subscribed podcasts are still excluded

Stripping affinity from the scoring isn't enough on its own. The user's centroid is built from episodes they've liked, whose titles and descriptions overwhelmingly come from podcasts they're already subscribed to — so **podcast affinity leaks through the centroid itself**. A pure content-similarity score will still rank subscribed-podcast episodes highly on shape alone, and the discovery list would collapse back to "your subscribed podcasts again" through the side door.

On top of that, candidate episodes from subscribed podcasts (i.e. ones that pass `Episode.candidate && id != onDeckID`) are exactly what UpNext already surfaces. Including them in a search-discovery list is duplicative with an existing surface that does the same job with the full scoring signal (affinity + freshness included).

So the collector **excludes subscribed podcasts entirely**. Every podcast it processes is unsubscribed: RSS fetch → parse → embed → score. There is no cheap path.

This applies uniformly to both surfaces. The "Top" trending chip in particular tends to overlap heavily with what most users already subscribe to — that's fine; the survivors-after-exclusion pool just ends up smaller, and the P-cap (see below) handles a short list gracefully. The point of the discovery surface is *new* content, so dropping subscribed-podcast matches is the desired behavior, not a degradation.

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

A single banner component renders just above the shared `resultsView` grid in both `searchResultsView` and `trendingView` (`SearchView.swift:122` and `SearchView.swift:151`). In the trending case it sits between the category chips and the grid; in the search case, between the search field area and the grid. It renders only when:

- The cached `ScoringContext` exists (engine `start()` has hydrated). Cold-start users with no rated episodes get no banner — there's nothing to score against.
- The collector has at least one scored episode buffered.

Label format depends on the active surface, derived from the collector's `source`:

- Typed search: `"Top \(count) from \"\(query)\" →"`.
- Trending category with a `genreID`: `"Top \(count) from \(section.title) →"`.
- Trending "Top" chip (no `genreID`): `"Top \(count) picks →"` — the category title here is just "Top," which would read awkwardly inlined ("Top 14 from Top →").

Tapping pushes the discovery list onto the search tab's navigation stack.

### 3. The collector — `PodHaven/Recommendations/SearchRecommendationCollector.swift` (new)

A `@MainActor` `@Observable` class owned by `SearchViewModel`. One instance at a time, bound to whichever surface is currently active. The previous instance is cancelled whenever the bound surface changes — that means a new query, a new trending category chip, or a flip between search-mode and trending-mode.

The collector carries a `source` enum to drive the banner label and discovery-list title without callers reaching into its internals:

```swift
enum Source: Sendable, Equatable {
  case search(query: String)
  case trending(genreID: Int?, title: String)
}
```

Responsibilities:

- Observe its bound podcast list (`searchResults` for `.search`, `currentTrendingSection.results` for `.trending`). When new results arrive, take the first **P** by surface-provided ranking, **then drop any the user is subscribed to** (see "Why subscribed podcasts are still excluded" above), then enqueue the survivors that aren't already in the seen-set. The cap happens *before* the subscription filter — we don't walk deeper into the result list to backfill the discovery budget, since the 30th-ranked result has no business being shown as a "top pick."
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

- The collector holds its root `TaskGroup` (or stored child Tasks). On `deinit`, on source change (query change, category chip change, or search↔trending flip), and when the user navigates out of the search tab, all in-flight Tasks are cancelled. URLSession requests cancel cleanly through `DownloadManager`; embedding work checks `Task.isCancelled` between episodes.
- The published `episodes` array is the collector's source of truth — it persists for the collector's lifetime (i.e. for as long as the bound surface is unchanged and search is on-screen) and is dropped when the collector is.

### 4. Discovery list view

A new `EpisodeListable` source backed by the collector's `episodes` array. The existing `EpisodesListView` already renders any `EpisodeListable` collection, so the integration is:

- A bridge type that wraps `[ListedEpisode]` — every entry is the `UnsavedPodcastEpisode` case (carrying the RSS-derived episode + the collector's `RecommendationScore` for sorting), since the collector only surfaces episodes from unsubscribed podcasts.
- The view's navigation title is the search query string for `.search`, or the category title for `.trending` (and just "Top picks" for the unbranded "Top" chip). Subtitle (if the existing view supports one) shows "Recommended for you" or similar.
- Sort is fixed: score desc, then pubDate desc, then guid. The standard sort toolbar is hidden here — the whole point of this view is "ranked by recommendation," and exposing the sort menu would invite a confusing "what does the engine think of these in pubDate order?" reading.
- Tapping an episode opens the existing episode detail view. **Verify** that the detail-view + play path handles `UnsavedPodcastEpisode` end-to-end without subscribing (this should already work — Search already lets users play episodes from unsubscribed podcasts — but worth confirming as part of implementation).

### 5. Search VM integration — `PodHaven/Views/Search/Models/SearchViewModel.swift`

- Hold an optional `collector: SearchRecommendationCollector?`.
- Recreate the collector on any surface change:
  - Query change (existing branches around `SearchViewModel.swift:404`) → new `.search(query:)` collector bound to `searchResults`.
  - `showTrendingSection(_:)` (`SearchViewModel.swift:259`) → new `.trending(genreID:title:)` collector bound to `currentTrendingSection.results`.
  - Flip between search-mode and trending-mode (driven by `isShowingSearchResults`) → tear down whatever's bound and rebind to the now-active surface.
- Expose `collector?.episodes.count` and `collector?.source` so the banner view can render its label without reaching into the collector directly.

---

## Scoring nuances

- **Centroid availability.** `discoveryScores(for:)` returns empty when the engine cache is cold. The banner stays hidden in that case — there's no graceful "partial discovery" mode worth building before the user has any liked/loved episodes. Cold-start cohort is small.
- **Negative centroid.** If the user has disliked episodes, the negative centroid is subtracted as today. This is desirable for discovery — content the user has actively rejected shouldn't bubble up via search.
- **English-only embeddings.** `NLContextualEmbedding` is English in this app's recipe (`EmbeddingService.swift:13–25`). Episodes whose title/description can't be embedded are silently skipped. Acceptable for v1; non-English handling is a separate concern.
- **No freshness penalty.** Stated explicitly because it differs from UpNext. A 2018 episode of a newly-discovered podcast that perfectly matches the user's taste should rank above a 2026 episode that doesn't.

## Cancellation & cost ceiling

At the starting `P = 25`, `E = 10` caps, every enqueued podcast is unsubscribed, so every podcast costs one RSS fetch (200ms–2s, parallel) + E embeddings (~10ms each on-device). Typical case is **3–8s wall clock** at utility priority, RSS-bound. If a surface returns mostly subscribed podcasts (e.g. the user searches a term that matches several of their subscriptions, or selects the "Top" trending chip on a heavily-curated subscription list), the collector fills its P budget from fewer results and may end up with a shorter list — acceptable, and arguably correct: those subscribed matches are UpNext's job.

Cancellation matters because users tab out of search quickly *and* chip-flip rapidly between trending categories. Per the lifecycle decision, every source change cancels every in-flight Task — no zombie network requests or embeddings continuing after the user has moved on. The cost of this is real for the trending surface: tapping Comedy → Technology → Comedy in quick succession pays the full RSS+embed cost three times in v1. The persisted-embedding cache below is the planned mitigation; absent that cache, chip toggling is genuinely expensive and worth measuring before deciding whether v1 ships with a debounce window between chip tap and collector spin-up.

---

## Deferred: persisted embedding cache for discovery

Not part of v1. Captured here so the option exists when/if the "embed-on-every-collector-spin-up" approach proves too slow or too power-hungry. **None of what follows applies to v1** — v1 doesn't persist anything new. Subscribed-podcast embeddings already live in `episodeEmbedding` and the existing versioning there handles itself; unsubscribed-podcast embeddings are computed and discarded inside the collector. The recipe-version / eviction concerns below only become real once we decide to *keep* unsubscribed-podcast embeddings on disk between collector lifetimes.

### Why we might want it

Embedding work is repeated every time a surface respawns the collector. Two scenarios dominate:

- **Repeat queries.** A user who searches "naval ravikant" twice pays the full embedding cost for that podcast's episodes twice.
- **Trending chip toggling.** This is the bigger driver now that trending is in v1. The trending grid invites rapid back-and-forth between categories — tap Comedy, tap Technology, tap back to Comedy — and each tap re-fetches and re-embeds the same set of top podcasts in that genre. The top-48 lists for established genres are also extremely stable hour-to-hour, so the same vectors get recomputed on every visit. This is the case the cache pays for most clearly.

With a persisted cache, both scenarios become nearly instant (RSS-fetch-bounded only — and even RSS responses get URLSession-level conditional caching via `Last-Modified` / `ETag`).

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

A first pass would measure: how much CPU/battery does v1 actually use across a realistic session — both typed searches and chip-flipping — and how often the same input (query or genre) recurs within the eviction window. The trending-chip case alone is likely to justify this cache; the search-repeat case is gravy.

---

## Risks & open questions

These are the things that aren't quite settled by the design above — surface them during implementation rather than chasing them in this doc.

- **Episode actions from an unsubscribed podcast.** When a discovery-list episode is from an unsubscribed podcast, tapping it produces an `UnsavedPodcastEpisode` instead of a DB-backed `ListablePodcastEpisode`. Search today lets you play those, but it's not obvious every downstream action (queue, like/dislike, rate, detail view, share) is wired up for the unsaved case. Worth walking each one through end-to-end during implementation. If something *does* require a real DB row, decide whether to silently materialize one, trigger the subscribe flow, or disable that action in this surface.
- **Does cancelling the collector actually cancel its RSS downloads?** A user typing quickly — or chip-flipping rapidly between trending categories — triggers a new collector per change, each one cancelling its predecessor. If `DownloadManager` keeps the URLSession task alive past the cancel, then re-issuing the same feed URL in the new collector might return the cancelled task's result instead of starting a fresh fetch. Verify cancellation propagates all the way down to the URLSession task, not just to the Swift `Task` wrapper.
- **Chip-toggle thrash.** Tapping Comedy → Technology → Comedy in a few seconds spins up three collectors and pays the full RSS+embed cost three times in v1 (the persisted-embedding cache is what makes this cheap, and it's deferred). Need a measurement pass on real device. If the cost is bad, a short debounce before spinning up the collector (e.g. wait 300ms for the chip to stay stable) is the smallest mitigation that avoids over-investing before the cache lands.
- **Late-arriving banner causes a layout jump.** Results render the moment the iTunes call returns (for typed search) or the trending fetch completes. The banner can't render until the collector has at least one scored episode, which is 1–3 seconds later in the typical case. The result is the grid laying out, then the banner popping in above it and shifting everything down. Acceptable, or worth a stub banner ("Finding top picks…") that holds the space from the start? UI-pass decision.
- **Banner stickiness across surface flips.** Typing in the search field flips from trending-mode to search-mode and vice versa via the search field clearing. Default behavior is strict tear-down (a partly-built Technology discovery list is discarded when the user starts typing, and rebuilt for Technology if they return to the trending chip). This matches the query-change behavior and avoids stale-context surprises, but means visible work is thrown away on every flip — revisit if measurements show users flipping often.

## Non-goals

- Changing the underlying recommendation algorithm. This initiative is a new *surface* for the existing engine, not a tuning pass on similarity weights, freshness, or affinity.
- Surfacing discovery recommendations anywhere other than the search tab. No notification, no home screen widget, no UpNext integration.
- Cross-surface ranking. Each query or trending category gets its own collector and its own ranking — we don't accumulate a global "best discovery candidates" pool across searches or across chips.
- Persistent results. The discovery list is recomputed every time a surface respawns the collector. Same search or same chip tomorrow re-fetches RSS and re-embeds (modulo the deferred caching above).
