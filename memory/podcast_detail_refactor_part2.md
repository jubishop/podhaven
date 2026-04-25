# Podcast Detail Refactor, Part 2

Saved 2026-04-24.

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

## Part 2 Ideas

The remaining complexity is probably around `SearchResultPodcast` and `ListedPodcast`, not
`PodcastDetailViewModel`.

Main question: does `SearchResultPodcast` still need to be a wrapper type, or should search/list rows
be modeled as a more explicit enum/data type?

Potential direction:

- Replace some type-erased wrapper behavior with an explicit list-row seed/model, e.g. cases for saved
  listable podcasts, unsaved search results, and saved search results with original search metadata.
- Preserve the existing public behavior that `ListedPodcast.id` uses the search result feed URL for
  bridged search results, while detail uses the saved feed URL for share/lookup.
- Keep detail initialization focused on `PodcastDetailSeed`; avoid reintroducing a detail-specific
  source/snapshot object.
- If `SearchResultPodcast` remains, narrow its role and make the name/purpose more obvious: it is a
  search/list bridge for saved podcasts, not a general podcast detail source.
- Consider whether the same approach should later apply to episode detail, but do not mix that into
  this part unless it falls out naturally.

## Safety Notes

- Test behavior through public view-model/list APIs, not private helper internals.
- Preserve or add tests for:
  - saved search results preserving initial search metadata before detail hydration
  - listable saved podcasts hydrating without feed parsing
  - preloaded unsaved/shared podcast series displaying episodes immediately
  - search result identity separation and `ListedPodcast.id` behavior
- Do not proceed with the `SearchResultPodcast` cleanup unless these behaviors are covered first.
