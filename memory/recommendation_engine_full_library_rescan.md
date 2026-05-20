---
name: recommendation-engine-full-library-rescan
description: Active investigation (#296) — RecommendationEngine rescans the entire ~95.5K-episode library on every Unqueued-list display / tab switch, pegging the app. Distinct from the #293 PodcastDetail storm; same architectural pattern.
type: project
---

# RecommendationEngine full-library rescan (#296)

Active investigation. Confirmed from a diagnostic TestFlight build.

## The bug

`EpisodesListViewModel.startDisplayObservation` (the Unqueued list) →
`kickRecommendationFetch` → `RecommendationEngine.scoreEpisodes` /
`embeddings(for:)` loads and scores the **entire episode library** on every
list display and every tab switch back to Episodes. On a large library each
pass is 0.4–2.2 s of CPU plus repeated 0.4–1.6 s ~95K-row SQLite reads. Rapid
tab navigation stacks them: the app spends most of its wall-clock time scoring,
the `DatabasePool` reader pool is saturated by the giant reads, and lightweight
UI / queue observations stall — lists won't load, queue/unqueue taps take
several seconds. No crash, no error-level event, so nothing alerts.

## Evidence

Sentry feedback `podhaven:7495117741` ("Can't even queue an item and see it
come off the unqueued list") + `podhaven:7495118557` ("Can't even unqueue") —
build `1.0+499`, commit `8a4aa613`, 2026-05-20. In the 71 s cold-launch
incident session:

- 9 full `embeddings(for:)` loads of ~95,500 embeddings (0.40–1.64 s each).
- 4 full `topRecommendations` passes (0.64–2.17 s each).
- `WriteProbe` showed DB writes were normal (~2.6 commits/s, all single-row
  feed refresh) — not a write storm. The "DB slammed" feeling is heavy *reads*.
- No #293 PodcastDetail storm signature — the reporter never opened a detail
  view this session, confirming this is a separate pathway.

## Root cause (two compounding parts)

1. **No coalescing.** `kickRecommendationFetch` re-fires on every Unqueued-list
   display observation / tab switch, with no debounce or dedup of unchanged
   inputs. The #274 scoring coalescer exists but does not cover this path.
2. **Each fetch is O(entire library).** `scoreEpisodes` scores all ~95.5K
   candidates for a top-10; `embeddings(for:)` re-reads and re-decodes the full
   embedding set from SQLite on every call, with no in-memory cache.

Cost scales with total library size — invisible on small / Simulator DBs,
severe on the reporter's 96,037-episode library. Explains why it never
reproduced in the Simulator.

## Open / next

- Confirm whether `scoreEpisodes` / `embeddings(for:)` run on the main actor,
  and the `DatabasePool` reader-pool size — decides whether the fix needs
  off-main isolation / a dedicated connection.
- Fix direction: coalesce/debounce `kickRecommendationFetch`; cache the
  embedding matrix in memory, invalidating only on embedding writes instead of
  re-reading ~95K rows per call.

## Related

- [[podcast_detail_recommendation_storm]] — #293, the sibling bug: same
  architectural weakness (a SwiftUI observation triggering uncoalesced heavy
  work), different loop. Either one alone pegs the whole app.
- [[recommendation_sort_prewarming]] — recommendation behaviour a fix must preserve.
