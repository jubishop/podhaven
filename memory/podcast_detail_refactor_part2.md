# Podcast Detail Refactor, Part 2

Saved 2026-04-24.
Reviewed 2026-04-24 after part 1 landed as `787c881`.
Implemented 2026-04-24.

## Context

The first pass simplified podcast detail navigation by replacing the `PodcastDetailSnapshot` and
`PodcastDetailSource` pair with `PodcastDetailSeed`.

That pass intentionally kept `SearchResultPodcast` and most list/search modeling intact. The goal was
to remove the extra detail-specific abstraction without taking on the deeper search/list model cleanup
in the same change.

## What Changed In Part 1

- `PodcastDetailSeed` now owns the initial presentation for:
  - an existing `DisplayedPodcast`
  - a `ListedPodcast`
  - a preloaded `UnsavedPodcastSeries`
- `PodcastDetailViewModel` directly resolves saved series and parses feed presentation.
- `DisplayedPodcast` no longer knows about detail snapshots.
- `PodcastDetailSnapshot` and `PodcastDetailSource` were deleted.
- The critical behavior to preserve is that searched saved podcasts can open detail immediately with
  the search result metadata, then hydrate to saved detail.

## Part 1 Review

Still agree with the part 1 shape as landed in `787c881`.

- `PodcastDetailSource` was mostly a carrier for initial presentation plus two fetch helpers, so
  moving those helpers into `PodcastDetailViewModel` is reasonable and removes the detail-specific
  source abstraction without hiding control flow.
- `PodcastDetailInitialPodcast` keeps the old snapshot behavior private to `PodcastDetailSeed`, which
  is the right boundary for now: detail still receives a seed, not a broad list/search wrapper.
- The important searched-saved behavior is covered: initial detail presentation uses search result
  description/link metadata, while share/lookup use the saved canonical feed URL and `performAppear()`
  hydrates to the saved podcast.
- The listable saved podcast path correctly marks the initial presentation as hydrating because the
  lightweight list model lacks detail-only fields.
- The preloaded unsaved/shared podcast series path displays episodes before `appear`, avoiding an
  unnecessary feed reparse.
- Episode detail still has `EpisodeDetailSource`/`EpisodeDetailSnapshot`; leave that alone unless a
  later episode-specific pass is deliberately scoped.
- The `AnyHashable` simplification in `DisplayedPodcast`/`ListedPodcast` is acceptable for part 1,
  but it also reinforces the part 2 motivation: these wrappers still allow broad existential storage
  where an explicit row/seed model would make the supported cases and identity rules easier to audit.

## Part 2 Plan

The remaining complexity is probably around `SearchResultPodcast` and `ListedPodcast`, not
`PodcastDetailViewModel`.

Main question: does `SearchResultPodcast` still need to be a wrapper type, or should search/list rows
be modeled as a more explicit enum/data type?

Preferred direction:

- Replace `ListedPodcast`'s `any PodcastListable` storage with an explicit enum or row model, e.g.
  cases for saved listable podcasts, unsaved search results, and saved search results with original
  search metadata.
- Either remove `SearchResultPodcast` entirely or narrow it into a clearly named data payload for the
  saved-search bridge case.
- Preserve the existing public behavior that `ListedPodcast.id` uses the search result feed URL for
  bridged search results, while detail uses the saved feed URL for share/lookup.
- Make the row identity rule explicit in the type: search result slot identity is not always the same
  as canonical podcast feed identity.
- Keep detail initialization focused on `PodcastDetailSeed`; avoid reintroducing a detail-specific
  source/snapshot object or moving search/list behavior into the detail view model.
- If `SearchResultPodcast` remains, narrow its role and make the name/purpose more obvious: it is a
  search/list bridge for saved podcasts, not a general podcast detail source.
- Consider whether the same approach should later apply to episode detail, but do not mix that into
  this part unless it falls out naturally.

Suggested execution order:

1. Start by locking down public behavior with tests around row identity, saved search result metadata,
   deletion reversion, and detail hydration.
2. Convert `ListedPodcast` from an existential wrapper into an explicit enum/row model while preserving
   its public API at call sites where practical.
3. Move bridge-only fields (`resultFeedURL`, original unsaved podcast, original episode count, original
   most recent date) onto that explicit row model or a nested bridge payload.
4. Update `SearchViewModel` construction/reversion helpers to use the explicit cases instead of
   downcasting through `getSearchResultPodcast()` / `getUnsavedPodcast()`.
5. Leave `PodcastDetailSeed` mostly unchanged; it should consume the clearer listed row and build the
   same initial presentation as part 1.

## Safety Notes

- Test behavior through public view-model/list APIs, not private helper internals.
- Preserve or add tests for:
  - saved search results preserving initial search metadata before detail hydration
  - listable saved podcasts hydrating without feed parsing
  - preloaded unsaved/shared podcast series displaying episodes immediately
  - search result identity separation and `ListedPodcast.id` behavior
- These behaviors were covered before the cleanup proceeded.

## Part 2 Result

Part 2 replaced `ListedPodcast`'s existential storage with explicit row cases:

- `saved(ListablePodcast)`
- `unsavedSearchResult(UnsavedPodcast)`
- `savedSearchResult(SavedSearchResultPodcast)`

`SavedSearchResultPodcast` is now a bridge payload, not a general `PodcastListable` wrapper. It keeps
the search result feed URL plus original search metadata and the canonical saved listable podcast.

`SearchViewModel` now builds and reverts search/trending rows through the explicit cases and
`ListedPodcast.SearchMetadata`, instead of downcasting through `getSearchResultPodcast()` /
`getUnsavedPodcast()`.

`PodcastDetailSeed` remained the detail boundary. It consumes the clearer `ListedPodcast` row model
and preserves the part 1 behavior: saved search results open with original search description/link
metadata while share/lookup use the canonical saved feed URL.

Focused verification passed with:

```sh
xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/PodHaven-seedRefactor2-dd -only-testing:PodHavenTests/ListedPodcastTests -only-testing:PodHavenTests/PodcastDetailViewModelTests -only-testing:PodHavenTests/SearchViewModelTests
```
