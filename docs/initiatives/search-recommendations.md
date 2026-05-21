---
status: planning
---

# Search Recommendations

Rank episodes from search results and trending-category chips with the existing
recommendation engine, then expose a "top picks from these results" list from
the search tab. The search surface is still planned; the lower-level scoring
pieces are already shipped.

## Current Code Baseline

- `RecommendationEngine` has two scoring paths. `recommendations(for:)` scores
  DB-backed `Episode` / `CandidateEpisode` values with similarity, podcast
  affinity, and freshness. `similarityScore(forEmbedding:)` scores a caller
  supplied vector by content similarity only, using the cached positive and
  negative centroids plus the same whitening/decone transform. It returns `nil`
  while the cache is cold or the vector dimension is wrong.
- `EmbeddingService.embeddingVector(for:embedding:)` builds an unsaved episode
  vector with the same title/description, podcast-context, normalization, and
  recipe-version semantics as saved episode embeddings. `EpisodeDetailViewModel`
  already uses this for unsaved episode detail scores, and
  `PodcastDetailViewModel` already uses it for recommendation-score sorting of
  unsaved podcast-detail episodes.
- `SearchViewModel` currently owns two podcast-result surfaces:
  `searchResults`, filled by `iTunesService.searchedPodcasts(..., limit: 48)`,
  and `currentTrendingSection.results`, filled by
  `iTunesService.topPodcasts(genreID:limit: 48)`. Trending includes "Top" plus
  Arts, Business, Comedy, Education, Government, Health, History, Kids, Leisure,
  Music, News, Science, Society & Culture, Sports, Technology, True Crime, and
  TV & Film.
- Each `TrendingSection` owns its fetched `results` and `task`.
  `loadTrendingSection` skips sections that are already `.loaded` or `.loading`,
  so top-category podcast rows stay cached while the Search tab is alive and
  repeat chip switches can be instant after first load.
- Search and trending results are
  `PodcastWithEpisodeMetadata<ListedPodcast>` rows, not episode rows. Episodes
  usually are not in the local DB unless the user subscribes or has interacted
  with them.
- `SearchView` has shared grid/list rendering but no recommendation banner.
  `Navigation.Destination` has podcast and episode routes but no
  search-discovery list route. `SearchView.onDisappear` currently resets search,
  trending, and observation work, so implementation must verify whether it fires
  when pushing deeper in the search navigation stack before using it for
  collector teardown.
- `DownloadTask.cancel()` is owner-aware: direct cancellation removes pending or
  active manager state, frees the download slot, and cancels the underlying
  fetch task. The collector should use this rather than adding a parallel
  downloader.

## Product Behavior

When the active search-tab surface has podcast results and similarity scoring is
available, show a compact banner above the shared results grid/list:

- Typed search loading: `Finding top picks from "\(query)"...`
- Typed search loaded: `Top \(count) from "\(query)" ->`
- Trending category loading: `Finding top picks from \(title)...`
- Trending category loaded: `Top \(count) from \(title) ->`
- Trending "Top" loading: `Finding top picks...`
- Trending "Top" loaded: `Top \(count) picks ->`

The loading banner is not tappable. Once at least one scored episode is buffered,
tapping pushes a search-specific discovery episode list. The list title is the
query, the category title, or `Top picks` for the unbranded "Top" chip.

Discovery uses content-similarity-only scoring. Podcast affinity and freshness
answer "what should I play next from my library"; this surface asks "which
episodes from these external results look like my taste." A 2018 perfect match
should beat a fresh weak match, and affinity would mostly pull the list back
toward already-loved shows.

Subscribed podcasts are excluded entirely. The user's centroid is built from
subscribed-library history, so even pure similarity tends to favor subscribed
shows. Candidate episodes from subscribed podcasts are already UpNext's job,
with the full scoring signal. This discovery list should spend network and
embedding work only on unsubscribed podcasts.

Scores stay invisible in the list. They are ranking metadata only. Episode
detail may still show its own saved recommendation score or unsaved similarity
score by recomputing through the existing detail-view path.

## V1 Implementation Shape

Add `SearchRecommendationCollector`, a `@MainActor @Observable` object owned by
`SearchViewModel` for the lifetime of the Search tab. The collector should mirror
the existing top-category result cache: keep computed recommendation work in
memory across top-category chip switches, and clear it when the user really
navigates away from Search.

```swift
enum Source: Sendable, Equatable {
  case search(query: String)
  case trending(genreID: Int?, title: String)
}
```

The collector maintains two cache layers:

- A shared podcast cache keyed by normalized, reconciled feed URL. Each entry
  owns the podcast's RSS fetch/parse state, candidate episode snapshots,
  embedding/scoring state, scored episodes, and score map. This cache is
  source-agnostic, so a podcast that appears in "Top", Comedy, and Technology is
  downloaded, embedded, and scored once.
- A top-category source index keyed by `Source.trending`, where each category
  stores only the ordered feed URLs selected from its current iTunes result
  snapshot. Do not copy scored episodes into each category. Build the active
  category output by walking that category's feed URL array, reading shared
  podcast cache entries, applying the score floor, and sorting the resulting
  episodes.

Typed search is intentionally different. Do not add typed-search result sets, or
podcasts discovered only through typed search, to the long-lived top-category
cache. A new debounced query should build a per-query overlay: first check the
shared podcast cache so results can reuse top-category podcasts that were
already scored, then fetch/score any query-only misses into overlay storage that
is discarded on the next query, on mode flip back to trending, or when Search is
left. This bounds memory for arbitrary search terms while still reusing category
work when the same podcast appears in search.

One stored `Task(priority: taskPriority(.utility))` should drain pending feed
URLs. Switching to a new top category updates the active source, records that
category's feed URL array if needed, and adds only feed URLs missing from the
shared cache or in-flight set to the utility worker. Do not cancel already-scored
or in-flight category podcast work just because the active category changed.
Replacement/cancellation should happen for the typed-search overlay when the
query changes, and for all collector work when Search is torn down. Keep the
existing 400 ms search debouncer for iTunes search execution; use a separate 1
second stable-query debounce before starting typed-search RSS fan-out.

Collector flow:

1. Take the first `P = 25` podcasts from the surface-provided ranking.
2. Reconcile that batch against the DB by feed URL and iTunes ID, matching the
   current `SearchViewModel` observation behavior. Do not trust only
   `ListedPodcast.subscribed`, because an unsaved iTunes result can bridge to an
   existing saved podcast after observation.
3. Drop subscribed podcasts. Do not backfill deeper than `P`; lower-ranked
   source results should not become "top picks" just because the first page was
   already subscribed.
4. Store the remaining ordered feed URLs in either the top-category source index
   or the current typed-search overlay. For top categories, point each feed URL
   at the shared podcast cache. For typed search, point at the shared cache when
   an entry already exists; otherwise point at query-local overlay storage.
5. For each cache miss, fetch and parse RSS through `DownloadManager`. Store the
   returned `DownloadTask` and call `await downloadTask.cancel()` when the child
   task is cancelled.
6. Take the newest `E = 10` episodes by `pubDate`.
7. Apply the existing candidate gate to materialized matches only. Resolve
   existing rows under the reconciled unsubscribed podcast ID, with exact
   `(guid, mediaURL)` matching as a fallback; avoid a broad unscoped
   `guid IN (...) OR mediaURL IN (...)` query. Existing rows must satisfy
   `Episode.candidate && id != onDeckID`; rows with no DB match pass through.
8. Embed each surviving `UnsavedPodcastEpisode` through
   `EmbeddingService.embeddingVector(for:embedding:)`. Skip and log individual
   embedding failures instead of failing the whole source.
9. Score with `RecommendationEngine.similarityScore(forEmbedding:)`, or a batch
   wrapper with the exact same semantics if profiling shows per-vector calls are
   too awkward.
10. Publish scored episodes keyed by `(feedURL, guid)` or the existing
   `MediaGUID` shape plus feed provenance, keep a `Float` score map, and re-sort
   on insert. Updating one shared podcast cache entry should update every active
   or cached top-category source that references its feed URL.

Initial caps are tunable constants near the collector: `P = 25`, `E = 10`, score
floor `score > 0.5`. The floor is separate from UpNext's `0.1` threshold because
discovery removes freshness, so neutral content clusters around the remapped
`0.5` baseline.

Throttle RSS and embedding separately. RSS can run with a small parallel cap;
embedding should start serialized or under a tiny cap around the shared
`ContextualEmbedding` until measurement proves wider concurrency is safe.

The collector owns one stored root task or explicit child handles. Task groups
must not escape their closure. Cancel typed-search overlay work on query
replacement. Cancel all shared category work on collector deinit or leaving the
search tab. Check cancellation between episodes and cancel any in-flight
`DownloadTask`.

## View Model And Navigation

`SearchViewModel` should expose the active collector source, loading state, and
visible count so `SearchView` can render the banner without reaching into
collector internals. Current code has no direct "similarity context is ready"
boolean; either add a small read-only readiness surface to `RecommendationEngine`
or publish the banner loading state only after the collector proves scoring can
succeed. Do not infer readiness from `scoringRevision` alone, because a revision
can still correspond to a nil scoring cache.

Add a search-navigation destination for the discovery list. The search path is a
plain `PathManager`, not a persisted `SavedPathManager`, and discovery results
should remain ephemeral. Category-scoring cache may live for the current Search
tab visit, but must be released when Search is left.

The discovery list should have its own lightweight view model rather than
reusing `EpisodesListViewModel` unchanged. That existing list model is coupled
to SQL observation and saved DB rows. Reuse the generic pieces that already work
with `ListedEpisode`: `PowerList<ListedEpisode>`, `EpisodeListView`, episode
swipe/context actions, and `.listedEpisode` navigation.

Sort is fixed: score descending, then `pubDate` descending, then GUID/media URL.
Hide the standard sort toolbar. Row actions that materialize or mutate an
episode (play, queue, cache, rate, mark finished) should remove that entry from
the collector's published array after success instead of trying to live-convert
the discovery row. Episode detail can handle its own unsaved-to-saved transition.
Tag UI stays hidden for unsaved rows until a materialized row is observed with
tags.

## Persistent Cache Deferred

V1 persists nothing new. The only durable-in-practice cache is in memory, scoped
to the active Search tab visit: shared category podcast scores plus the current
typed-search overlay. `SearchViewModel.disappear()` or the equivalent verified
Search-exit signal must clear it so arbitrary discovery candidates do not live
in memory forever.

If the in-memory Search-tab cache is still too slow or wasteful, add a local
discovery cache later:

- A parsed-feed cache keyed by normalized feed URL, with short TTL, conditional
  refresh metadata, and enough episode/podcast fields to rebuild
  `UnsavedPodcastEpisode` snapshots.
- A parallel `discoveryEpisodeEmbedding` table rather than forcing unsaved
  candidates into the existing `episodeEmbedding` table, which is `episodeId`
  backed by design.
- Keys based on feed URL plus GUID/media URL, with `embeddingRevision`,
  `recipeVersion`, dimension, and source hash so recipe changes invalidate stale
  vectors.
- Time-based plus least-recently-used eviction, with `lastAccessedDate` touched
  on reads.

This persistent cache would mainly pay off across Search-tab visits. The V1
in-memory cache already handles trending-chip toggling inside one visit, where
category feeds are stable and many categories share the same podcasts. Repeat
typed queries are not a V1 cache target because they can grow without bound.

## Risks And Follow-Ups

- **Banner lifecycle.** Preserve the collector while the pushed discovery list is
  visible. Do not let root `SearchView.onDisappear` discard the backing episodes
  if that disappear is only a navigation push.
- **Churn.** Category switches should enqueue only new feed URLs and reuse
  shared scored podcast entries. Typed-search churn should cancel and discard the
  previous query overlay without promoting query-only podcasts into the shared
  category cache.
- **Budget.** Log RSS count/duration, embedding count/duration, cancellation
  count, score-floor drops, and final visible count for typed search and
  trending. Use real-device data before changing P/E caps, concurrency, score
  floor, TTL, or eviction policy.
- **Tests.** Cover top-category feed URL index reuse, shared podcast cache reuse
  across categories, typed-search reuse of shared cached podcasts without adding
  query-only misses to the category cache, typed-query overlay replacement,
  Search-exit cache teardown, subscribed-podcast exclusion after feed URL/iTunes
  ID reconciliation, cancellation of active and pending downloads,
  candidate-gate filtering for materialized episodes, score ordering, and
  post-action removal.

## Non-Goals

- Changing the recommendation algorithm or weights.
- Surfacing these recommendations outside the search tab.
- Cross-query or cross-category ranking.
- Caching typed-search result sets across queries.
- Persistent discovery results in v1.
