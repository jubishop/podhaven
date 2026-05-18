---
status: in-progress
---

# Search Recommendations

Rank the episodes of podcasts returned from a search or a trending-category chip by the existing ML recommendation engine, surfacing a "top recommended episodes from these results" list as a discovery tool. Design captured 2026-05-11; still planning for the search surface itself. Updated 2026-05-16 to reflect shipped foundations: unsaved episode embedding/scoring, unsaved podcast-detail recommendation sorting, and owner-aware `DownloadTask.cancel()`.

## Context

The recommendation engine (`PodHaven/Recommendations/RecommendationEngine.swift`) now has two relevant scoring paths:

- `recommendations(for: [Episode])` / `recommendations(for: [CandidateEpisode])` score DB-backed episodes against the cached centroid + affinity + freshness context. These are used by UpNext, saved episode lists, and saved podcast-detail recommendation sorting.
- `similarityScore(forEmbedding:)` scores a caller-supplied vector by content similarity only. It is already consumed by `EpisodeDetailViewModel` for unsaved episodes and by `PodcastDetailViewModel` when sorting unsaved podcast-detail episodes by recommendation score.

The search tab has two primary podcast-list surfaces that share the same rendering:

- **Typed search results** — `SearchViewModel.searchResults` (`PodHaven/Views/Search/Models/SearchViewModel.swift:207`), populated from the iTunes search API when the user types a query.
- **Trending categories** — `SearchViewModel.currentTrendingSection.results`, populated from `iTunesService.topPodcasts(genreID:limit: 48)` (`SearchViewModel.swift:307`). One chip per genre — "Top" (no `genreID`) plus 17 categories: Arts, Business, Comedy, Education, Government, Health, History, Kids, Leisure, Music, News, Science, Society & Culture, Sports, Technology, True Crime, TV & Film.

Both surfaces yield `PodcastWithEpisodeMetadata<ListedPodcast>` — podcast-level results with lightweight episode metadata. The episodes themselves don't live in the local DB unless the user subscribes or has already interacted with an episode. This initiative bridges the gap: fetch the RSS feeds of the top podcasts from whichever surface is active, embed their recent episodes on the fly, score them through the engine, and present the result in a discovery episode list reached via a banner above the grid.

The intended outcome: any time a podcast-list surface in the search tab has results, a banner appears above the grid showing a running count. For typed search: `"Top 14 from \"naval ravikant\" →"`. For trending: `"Top 14 from Technology →"` (or `"Top 14 picks →"` for the unbranded "Top" chip). Tapping pushes a search-discovery episode list titled with the originating query-or-category, sorted descending by similarity score, that fills in episodes as background scoring completes.

### Why content-similarity-only scoring

The existing `similarityScore(forEmbedding:)` primitive scores by similarity to the user's centroid alone — no podcast affinity, no freshness gate. Both of those terms exist for a different question ("what should I play next from my subscriptions?") and would distort a discovery surface:

- **Affinity** would heavily bias the list toward podcasts the user already rates highly — irrelevant for unsubscribed podcasts (no rating history) and counter-productive for subscribed ones (the discovery list would become "your top subscribed podcasts again").
- **Freshness** is multiplicative (`RecommendationEngine.swift:712`), so a 2018 episode of a perfectly-matched podcast would be penalized into oblivion. For a search-driven view, the user's lens is content match, not recency.

### Why subscribed podcasts are still excluded

Stripping affinity from the scoring isn't enough on its own. The user's centroid is built from episodes they've liked, whose titles and descriptions overwhelmingly come from podcasts they're already subscribed to — so **podcast affinity leaks through the centroid itself**. A pure content-similarity score will still rank subscribed-podcast episodes highly on shape alone, and the discovery list would collapse back to "your subscribed podcasts again" through the side door.

On top of that, candidate episodes from subscribed podcasts (i.e. ones that pass `Episode.candidate && id != onDeckID`) are exactly what UpNext already surfaces. Including them in a search-discovery list is duplicative with an existing surface that does the same job with the full scoring signal (affinity + freshness included).

So the collector **excludes subscribed podcasts entirely**. Every podcast it processes is unsubscribed: RSS fetch → parse → embed → score. There is no cheap path.

This applies uniformly to both surfaces. The "Top" trending chip in particular tends to overlap heavily with what most users already subscribe to — that's fine; the survivors-after-exclusion pool just ends up smaller, and the P-cap (see below) handles a short list gracefully. The point of the discovery surface is *new* content, so dropping subscribed-podcast matches is the desired behavior, not a degradation.

---

## Architecture

### 1. Engine scoring primitive — `PodHaven/Recommendations/RecommendationEngine.swift`

Use the shipped content-similarity primitive:

```swift
func similarityScore(forEmbedding embedding: [Float]) -> Float?
```

It returns `nil` when the scoring cache is cold or the vector dimension doesn't match the cached centroid. Internally it applies the same whitening/decone transform used by saved-episode scoring, then cosines the candidate against the cached positive centroid and subtracts the negative centroid if present. It skips podcast affinity and freshness entirely.

The result is a display-rescaled `Float` in the same percentage scale used by saved detail views. That rescale is monotonic, so it preserves ordering for a discovery list, but it does mean discovery currently carries a numeric score only — no `RecommendationScore` reasons. If batch scoring becomes necessary for collector throughput, add a tiny batch wrapper with these exact semantics and caller-owned IDs; don't add a separate `RecommendationScore`-returning API unless the UI actually needs reasons.

This is additive — no changes to `recommendations(for:)` or `topRecommendations(limit:)`. Both keep their current contract for UpNext.

### 2. Unsaved episode embedding helper — `PodHaven/Recommendations/Embeddings/EmbeddingService.swift`

Shipped public helper, using the same recipe as saved-episode embeddings:

```swift
static func embeddingVector(
  for unsavedPodcastEpisode: UnsavedPodcastEpisode,
  embedding: ContextualEmbedding
) async throws -> [Float]
```

This helper shares the saved-episode recipe: clean title and description, title/description blend, podcast title/description vector, episode/podcast blend, and final normalization. It is `async` so `@MainActor` callers hop the CPU-bound embedding work and possible first-time model load off main. Discovery needs this vector shape without allocating an `Episode.ID` or writing an `episodeEmbedding` row. If contextual embedding assets are unavailable or the text produces no token vectors, the collector should skip that episode and log at debug/info rather than failing the whole podcast.

### 3. Banner placement — `PodHaven/Views/Search/SearchView.swift`

A single banner component renders just above the shared `resultsView` grid in both `searchResultsView` and `trendingView` (`SearchView.swift:122` and `SearchView.swift:151`). In the trending case it sits between the category chips and the grid; in the search case, between the search field area and the grid. It renders only when:

- The cached `ScoringContext` exists (engine `start()` has hydrated). Cold-start users with no usable positive signal get no banner — there's nothing to score against.
- The active surface has podcast results and a collector is pending, loading, or has at least one scored episode buffered.

Current code does not expose a direct "similarity context is ready" boolean; `similarityScore(forEmbedding:)` only reports readiness after a caller already has a vector. To show the loading/stub banner before the first scored episode, add a small read-only readiness surface on `RecommendationEngine` or let the collector publish a loading state only after it has proved scoring can succeed. Do not infer readiness from `contextRevision` alone, because a revision can still correspond to a nil cache.

Label format depends on the active surface, derived from the collector's `source`. While the collector is debouncing or loading and has no scored episodes yet, render a non-tappable loading/stub banner so the grid does not jump when the first recommendation arrives:

- Typed search: `"Finding top picks from \"\(query)\"…"`
- Trending category with a `genreID`: `"Finding top picks from \(section.title)…"`
- Trending "Top" chip (no `genreID`): `"Finding top picks…"`

Once the collector has at least one scored episode, the banner becomes tappable:

- Typed search: `"Top \(count) from \"\(query)\" →"`.
- Trending category with a `genreID`: `"Top \(count) from \(section.title) →"`.
- Trending "Top" chip (no `genreID`): `"Top \(count) picks →"` — the category title here is just "Top," which would read awkwardly inlined ("Top 14 from Top →").

Tapping the loaded banner pushes the discovery list onto the search tab's navigation stack. The collector must remain alive while that pushed discovery view is visible; source-change cancellation should not be triggered by a root `SearchView.onDisappear` caused only by pushing deeper in the search navigation stack. Cancel on explicit source change, collector deinit, or leaving the search tab.

### 4. The collector — `PodHaven/Recommendations/SearchRecommendationCollector.swift` (new)

A `@MainActor` `@Observable` class owned by `SearchViewModel`. One instance at a time, bound to whichever surface is currently active. The previous instance is cancelled whenever the bound surface changes — that means a new query, a fresh iTunes result snapshot for the same query/category, a new trending category chip, or a flip between search-mode and trending-mode. Starting replacement RSS work is debounced by 1 second so quick typing and chip taps do not immediately fan out network requests.

The collector carries a `source` enum to drive the banner label and discovery-list title without callers reaching into its internals:

```swift
enum Source: Sendable, Equatable {
  case search(query: String)
  case trending(genreID: Int?, title: String)
}
```

Responsibilities:

- Treat the bound podcast list (`searchResults` for `.search`, `currentTrendingSection.results` for `.trending`) as an immutable input snapshot. If iTunes returns a new result set for the same query/category, discard the current collector and build a new one after the 1-second debounce; do not merge new results into the old collector. Within a collector, take the first **P** by surface-provided ranking, then run a batch DB reconciliation by result feed URL and iTunes ID before deciding what is subscribed. Do not rely only on `ListedPodcast.subscribed`: iTunes rows start life as unsaved results and can bridge to an already-saved podcast after observation. After reconciliation, drop any result whose canonical podcast is subscribed, then enqueue the survivors that aren't already in the seen-set. The cap happens *before* the subscription filter — we don't walk deeper into the result list to backfill the discovery budget, since the 30th-ranked result has no business being shown as a "top pick."
- Take the most recent **E** episodes per enqueued podcast (by `pubDate` desc). Starting values: `P = 25`, `E = 10`. Both are **tunable** — they trade discovery surface area against RSS load + embedding cost, and the right values will fall out of measurement once the feature is wired up. Captured here as constants near the collector so they're easy to find and adjust. Note that with subscribed podcasts excluded, every enqueued podcast pays the full RSS+embed cost, so P caps the network/CPU load directly.
- For each enqueued podcast, fan out a child Task at `taskPriority(.utility)`:
  1. Fetch + parse RSS through `DownloadManager`. Issue #251 is closed and direct `DownloadTask.cancel()` is now owner-aware: the manager removes the active or pending task, starts the next queued download immediately, and cancels the underlying `URLSession.data(for:)` request. The collector should keep the `DownloadTask` returned by `addURL` and call `await downloadTask.cancel()` when its child Task is cancelled.
  2. Take the E most recent episodes from the parsed feed.
  3. Apply the candidate filter. Most episodes from these podcasts won't have a DB row at all (so the filter is a no-op for them), but the user *might* have interacted with one previously — played, queued, or rated an episode from a podcast they never subscribed to. Reuse the podcast reconciliation from the enqueue step and resolve existing episodes under the resolved unsubscribed podcast ID, plus exact `(guid, mediaURL)` composite matches as a fallback. Avoid a broad unscoped `guid IN (…) OR mediaURL IN (…)` query; GUIDs and media URLs are good natural keys, but the filter should not accidentally match an unrelated podcast row. For each match, apply `Episode.candidate && id != onDeckID` (`Episode.swift:254`) — which excludes finished, queued, started, rated, and onDeck episodes — and drop the failures. Episodes with no matching row pass through.
  4. For surviving episodes, call `EmbeddingService.embeddingVector(for:embedding:)` to produce a vector. Skip any episode that fails to embed.
  5. Pass each vector to `engine.similarityScore(forEmbedding:)`, or to a batch wrapper with the same semantics if profiling shows per-vector calls are too awkward.
- Merge scored episodes into the published `episodes` array, keyed by `(feedURL, guid)`, carrying a `Float` similarity score for sorting. Re-sort on every insert. UI observes and re-renders silently.
- Track a discovery-specific minimum-score floor near the neutral midpoint, not UpNext's `minimumScoreThreshold`. UpNext's `0.1` floor is tuned for scores that can be multiplied down by freshness; discovery removes freshness, so neutral candidates cluster around `0.5` and a `0.1` floor would admit almost everything. Starting point: require `score > 0.5`, then tune from real-device samples.
- Throttle the collector as two separate resources: RSS fetches can run with a small parallel cap, but embedding should be serialized or protected by a tiny concurrency cap around the shared `ContextualEmbedding` until measurement proves it is safe to run wider.

Cancellation lifecycle:

- The collector holds a stored root `Task<Void, Never>` that owns a `withTaskGroup` / `withThrowingTaskGroup`, or it stores explicit child `Task` handles. `TaskGroup` itself does not escape the closure. On `deinit`, on source change (query change, fresh iTunes result snapshot, category chip change, or search↔trending flip), and when the user leaves the search tab, cancel the root/children. RSS work uses the `DownloadTask` returned by `DownloadManager.addURL`; child cancellation calls `await downloadTask.cancel()`. Embedding work checks `Task.isCancelled` between episodes.
- The published `episodes` array is the collector's source of truth — it persists for the collector's lifetime (i.e. for as long as the bound surface is unchanged and search is on-screen) and is dropped when the collector is.

Post-action lifecycle:

- Discovery rows start as unsaved snapshots. Existing shared actions (`play`, queue, cache, rate, mark finished) may materialize the podcast/episode in the DB via `getOrCreatePodcastEpisode()`. In v1, after any successful action that materializes or mutates an episode enough to trip the candidate gate, remove that `(feedURL, guid)` from the collector's `episodes` array instead of trying to live-convert the discovery row to a DB-backed row. If the user is already on episode detail, the detail view's own transition/observation can move from unsaved to saved. The list's job is to avoid stale unsaved rows and avoid recommending something the user just acted on.

### 5. Discovery list view

A new search-specific list view and view model backed by the collector's `episodes` array. Do not wire this through the existing `EpisodesListView` unchanged: that view is still coupled to `EpisodesListViewModel`, SQL observation, `PowerList<ListablePodcastEpisode>`, and saved DB rows. But the newer `PodcastDetailViewModel` work proves that `PowerList<ListedEpisode>`, row actions, and unsaved similarity scoring already work for unsaved episodes, so the search-specific list should reuse those patterns instead of inventing a parallel row/action stack.

- Add a lightweight search-discovery view model that owns `PowerList<ListedEpisode>` plus a `[MediaGUID: Float]` score map, or a small wrapper if that makes the collector boundary cleaner. Every entry starts as the `UnsavedPodcastEpisode` case, since the collector only surfaces episodes from unsubscribed podcasts.
- The list can reuse row-level pieces (`EpisodeListView`, `episodeSwipeActions`, `episodeContextMenu`, `Navigation.Destination.listedEpisode`) because those are generic over `EpisodeListable` / `ManagingEpisodes` and already handle `ListedEpisode`. It still needs its own view model because filtering, sorting, loading state, and source updates are collector-driven rather than SQL-driven.
- The view's navigation title is the search query string for `.search`, or the category title for `.trending` (and just "Top picks" for the unbranded "Top" chip). Subtitle (if the existing view supports one) shows "Recommended for you" or similar.
- Sort is fixed: score desc, then pubDate desc, then guid. The standard sort toolbar is hidden here — the whole point of this view is "ranked by recommendation," and exposing the sort menu would invite a confusing "what does the engine think of these in pubDate order?" reading. The score stays invisible in the list; rows render like normal episode rows, and the score is ranking metadata only.
- Tapping an episode opens the existing episode detail view through `.listedEpisode`. The detail-view + play path already has unsaved-to-saved transitions, but implementation should still walk play, queue, cache, rating, mark-finished, share, and tag affordances end-to-end for this surface. Tag UI should stay hidden for unsaved rows until a row has been materialized and observed with tags.

### 6. Episode detail recommendation scoring — `PodHaven/Views/Episodes/Models/EpisodeDetailViewModel.swift`

Issue #250 is closed. The discovery list does not show recommendation scores, but episode detail can now show a similarity score when the episode is backed only by an `UnsavedPodcastEpisode`. This does not depend on the discovery list passing a precomputed score; any unsaved episode detail opened from search/share/deep-link can compute its own score when the engine context is warm.

- Keep the existing saved-episode path: when the detail state is `.saved`, use `recommendationEngine.recommendation(for: episodeID)` so DB-backed episodes keep the normal UpNext-style score.
- Current unsaved path: when the detail state is `.unsaved`, compute and cache the vector with `EmbeddingService.embeddingVector(for:embedding:)`, then call `recommendationEngine.similarityScore(forEmbedding:)`. The view renders this through `EpisodeDetailDisplayedScore.similarity(Float)`, not a `RecommendationScore`, because there are no reasons for the content-only path.
- Start recommendation observation for both `.saved` and `.unsaved` states. The existing `contextRevision` stream can still drive re-fetches; the fetch method chooses the saved or unsaved scoring path based on current state. If an action materializes the episode and transitions state to `.saved`, subsequent refreshes naturally switch to the saved path.
- Preserve the existing display guard: once the episode is rated or finished, hide the score because the episode has become an explicit signal or completed item.
- Log and hide the section if the unsaved embedding cannot be computed because the contextual embedding model is unavailable or the text yields no vector. This should not block detail rendering or the play/queue actions.

### 7. Search VM integration — `PodHaven/Views/Search/Models/SearchViewModel.swift`

- Hold an optional `collector: SearchRecommendationCollector?`.
- Recreate the collector on any surface change, after a 1-second stable-source debounce:
  - Query change (existing search execution around `SearchViewModel.swift:357`) → new `.search(query:)` collector bound to `searchResults`.
  - Fresh iTunes result snapshot for the same query/category → cancel and rebuild from the new snapshot, because the server may have returned a materially different podcast ordering or feed set.
  - `showTrendingSection(_:)` (`SearchViewModel.swift:259`) → new `.trending(genreID:title:)` collector bound to `currentTrendingSection.results`.
  - Flip between search-mode and trending-mode (driven by `isShowingSearchResults`) → tear down whatever's bound and rebind to the now-active surface.
- Implement the debounce with the injected `Sleepable`/`sleeper` or an existing debounce helper, not `Task.sleep`, so tests can control timing.
- Keep this separate from the existing 400ms search debouncer. That debouncer controls when iTunes search runs; the collector's 1s debounce controls when RSS fan-out starts after a stable result snapshot exists.
- Show the loading/stub banner as soon as the active surface has results and the scoring context exists, even during the 1-second debounce. New source changes cancel any pending debounce task and replace the banner source immediately.
- Expose `collector?.episodes.count` and `collector?.source` so the banner view can render its label without reaching into the collector directly.
- Add a search-navigation destination for the discovery list, keyed by `collector.source` (or an explicit route object) so tapping the banner pushes a stable list bound to the current collector. `Navigation.Destination` currently has no discovery-list case. Do not persist this destination across launches; persistent results are a non-goal.
- `SearchView` currently calls `viewModel.disappear()` from `.onDisappear`, which resets search/trending tasks. Before using that hook for collector teardown, verify whether it fires when pushing deeper in the search navigation stack; if it does, move collector cancellation to explicit source changes and tab-leave handling so the pushed discovery list does not lose its backing collector.

---

## Scoring nuances

- **Centroid availability.** `similarityScore(forEmbedding:)` returns `nil` when the engine cache is cold. The banner stays hidden in that case — there's no graceful "partial discovery" mode worth building before the user has enough positive signal. Cold-start cohort is small.
- **Negative centroid.** If the user has disliked episodes, the negative centroid is subtracted as today. This is desirable for discovery — content the user has actively rejected shouldn't bubble up via search.
- **English-only embeddings.** `NLContextualEmbedding` is English in this app's recipe (`NLContextualEmbedding.swift:12-28`). Episodes whose title/description can't be embedded are silently skipped. Acceptable for v1; non-English handling is a separate concern.
- **No freshness penalty.** Stated explicitly because it differs from UpNext. A 2018 episode of a newly-discovered podcast that perfectly matches the user's taste should rank above a 2026 episode that doesn't.
- **Score floor.** Discovery uses a separate floor from UpNext. Start with `score > 0.5` because `0.5` is the remapped neutral similarity baseline; tune only after logging real candidate distributions.
- **Score display.** The discovery list does not show scores or reasons. Keep the `Float` score as ranking metadata only, and render normal episode rows. Episode detail may still show its existing recommendation/similarity section by fetching a saved score or computing an unsaved similarity score for itself.

## Cancellation & cost ceiling

At the starting `P = 25`, `E = 10` caps, every enqueued podcast is unsubscribed, so every podcast costs one RSS fetch (200ms–2s, parallel) + E embeddings (~10ms each on-device). Typical case is **3–8s wall clock** at utility priority, RSS-bound. If a surface returns mostly subscribed podcasts (e.g. the user searches a term that matches several of their subscriptions, or selects the "Top" trending chip on a heavily-curated subscription list), the collector fills its P budget from fewer results and may end up with a shorter list — acceptable, and arguably correct: those subscribed matches are UpNext's job.

Cancellation matters because users tab out of search quickly *and* chip-flip rapidly between trending categories. Per the lifecycle decision, every source change cancels every in-flight Task and the underlying URLSession work must be cancellable, not just the Swift wrapper waiting for a result. Issue #251 closed that gap in `DownloadManager`; the collector can use `DownloadTask.cancel()` directly. Collector startup also waits for a 1-second stable-source debounce; the loading banner appears during that delay, but RSS work does not start until the source remains stable. The cost of churn is still real for the trending surface: tapping Comedy → Technology → Comedy across several seconds can pay the full RSS+embed cost multiple times in v1. The persisted feed + embedding cache below is the planned mitigation.

---

## Deferred: persisted feed + embedding cache for discovery

Not part of v1. Captured here so the option exists when/if the "fetch-and-embed-on-every-collector-spin-up" approach proves too slow, too network-heavy, or too power-hungry. **None of what follows applies to v1** — v1 doesn't persist anything new. Subscribed-podcast embeddings already live in `episodeEmbedding` and the existing versioning there handles itself; unsubscribed-podcast feeds and embeddings are fetched/computed and discarded inside the collector. The feed TTL, recipe-version, and eviction concerns below only become real once we decide to *keep* unsubscribed-podcast discovery data on disk between collector lifetimes.

### Why we might want it

RSS fetch and embedding work repeat every time a surface respawns the collector. Two scenarios dominate:

- **Repeat queries.** A user who searches "naval ravikant" twice pays the full embedding cost for that podcast's episodes twice.
- **Trending chip toggling.** This is the bigger driver now that trending is in v1. The trending grid invites rapid back-and-forth between categories — tap Comedy, tap Technology, tap back to Comedy — and each tap can re-fetch and re-embed the same set of top podcasts in that genre. The top-48 lists for established genres are also extremely stable hour-to-hour, so the same feeds and vectors get reused on every visit. This is the case the cache pays for most clearly.

With a persisted feed + embedding cache, both scenarios become nearly instant when the same feeds appear again. URLSession conditional caching via `Last-Modified` / `ETag` is useful, but it still requires network round trips and reparsing; a local parsed-feed cache avoids that churn during quick search/trending bounces.

### Why we might not

- **Storage growth.** ~512 floats × 4 bytes = 2KB per embedding. P podcasts × E episodes × N distinct searches/day adds up to MBs/week of vectors the user may never see again.
- **Feed staleness.** A local parsed-feed cache can hide newly-published episodes until its TTL expires. That is acceptable for discovery because the feature is ranking likely-interesting episodes, not promising a live feed view, but the TTL should be short enough that repeated visits still feel fresh.
- **Cache invalidation cost.** The embedding recipe is versioned (`recipeVersion = 2`, `EmbeddingService.swift:15`). If we tune the recipe, every cached vector from the old recipe is wrong — they have to be discarded and recomputed. The cache earns its keep across long stretches of stable recipe, but every recipe bump wipes it.
- **Code complexity.** v1 has no persistence layer for discovery candidates at all. Adding one means new tables, feed TTL rules, embedding eviction policy, and code paths that have to stay correct under feed changes and recipe-version changes.

### Proposed shape (if/when we revisit)

- Prefer a parallel `discoveryEpisodeEmbedding` table rather than reusing `episodeEmbedding`. The existing `episodeEmbedding` table is intentionally `episodeId`-backed with a required FK to `episode`; forcing discovery candidates into it would either allocate real episode rows for things the user has not chosen or require a synthetic-ID/provenance layer that fights the current schema.
- Add a parallel parsed-feed cache keyed by normalized feed URL. Store enough structured episode data to rebuild `UnsavedPodcastEpisode` snapshots without reparsing XML: feed URL, podcast metadata used by the embedding recipe, recent episode GUID/mediaURL/pubDate/title/description/duration/image fields, `lastFetchedAt`, and any HTTP validators needed to refresh cheaply later.
- Give parsed-feed rows a short TTL plus conditional refresh. During quick chip/query bouncing, use fresh local rows directly; once stale, revalidate through `DownloadManager` with `ETag` / `Last-Modified` if available and update the parsed snapshot only when the feed changed.
- Key on `(feedURL, guid, mediaURL)` or a normalized composite derived from those values. `(feedURL, guid)` is the human-readable identity, but `mediaURL` is useful for feeds with unstable/missing GUIDs and for exact composite matching against any previously materialized episode.
- **Eviction policy.** Time-based (`creationDate < now - 30d`) plus a hard cap on row count. When the cap is hit, evict the **least-recently-used** rows first — i.e. the ones whose `lastAccessedDate` is oldest. ("LRU" is the common shorthand: Least Recently Used. The rule is "if the cache is full, throw out whatever you haven't touched in the longest time," on the theory that recently-used entries are likeliest to be used again soon.) Eviction runs as part of the existing periodic embedding maintenance task; the collector updates `lastAccessedDate` on every read.
- **Recipe-version invalidation.** Each row should carry `embeddingRevision`, `recipeVersion`, `dimension`, and a source hash built from the same cleaned episode + podcast text used by `EmbeddingService`. On read, rows whose revision/recipe/hash doesn't match the current recipe are dropped. On a recipe bump this empties the discovery cache over time; the collector falls back to recomputing.

A first pass would measure: how much network, CPU, and battery v1 actually uses across a realistic session — both typed searches and chip-flipping — and how often the same input (query or genre) recurs within the feed TTL / embedding eviction window. The trending-chip case alone is likely to justify this cache; the search-repeat case is gravy.

---

## Risks & follow-ups

These are settled implementation choices plus the remaining verification work to keep visible during implementation.

- **DownloadManager integration.** A user typing quickly — or chip-flipping rapidly between trending categories — triggers a new collector per change, each one cancelling its predecessor. The prerequisite is now done: direct `DownloadTask.cancel()` removes manager state, advances the queue, and cancels the underlying `URLSession.data(for:)` request. The collector should use that path instead of adding a separate downloader.
- **Chip-toggle thrash.** Tapping Comedy → Technology → Comedy in a few seconds should not spin up three immediate RSS fan-outs. v1 waits for a 1-second stable-source debounce before starting collector RSS work. If users still churn through network after that, the deferred parsed-feed + embedding cache is the next mitigation.
- **Banner loading state.** Results render the moment the iTunes call returns (for typed search) or the trending fetch completes. The banner should reserve space immediately with a loading/stub state ("Finding top picks…") while the collector debounces and scores, then switch to the count label once the first scored episode arrives.
- **Banner stickiness across surface flips.** Typing in the search field flips from trending-mode to search-mode and vice versa via the search field clearing. Default behavior is strict tear-down: a partly-built Technology discovery list is discarded when the user starts typing, and rebuilt for Technology if they return to the trending chip. Fresh iTunes data gets the same treatment because the server may return different podcasts. The deferred cache should make rebuilds cheap when many feeds/episodes overlap; keeping stale collectors alive is not the plan.
- **Real-device budget.** The doc assumes 3-8 seconds wall clock and cheap per-episode embedding, but v1 should log RSS count, RSS duration, embedding count, embedding duration, cancellation count, and final visible count for both typed search and trending. Use that data before changing P/E caps, concurrency caps, score floors, feed TTLs, or cache eviction policy.

## Non-goals

- Changing the underlying recommendation algorithm. This initiative is a new *surface* for the existing engine, not a tuning pass on similarity weights, freshness, or affinity.
- Surfacing discovery recommendations anywhere other than the search tab. No notification, no home screen widget, no UpNext integration.
- Cross-surface ranking. Each query or trending category gets its own collector and its own ranking — we don't accumulate a global "best discovery candidates" pool across searches or across chips.
- Persistent results. The discovery list is recomputed every time a surface respawns the collector. Same search or same chip tomorrow re-fetches RSS and re-embeds (modulo the deferred caching above).
