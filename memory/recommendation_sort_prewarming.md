---
name: recommendation-sort-prewarming
description: EpisodesListView scores recommendations on demand; PodcastDetailView still prewarms.
type: feedback
---

Recommendation-score sorting in `EpisodesListViewModel` is computed **on demand** — only while the `recommendationScore` sort is the selected one. It is NOT prewarmed in the background on other sorts. `PodcastRecommendationScorer` (PodcastDetailView) still prewarms on appear.

**Why:** Issue #310 — constant background scoring on every Episodes-list display / tab switch was too costly and complex. The user accepts a one-time "Computing recommendations…" wait when first selecting the rec sort; snappiness on re-selection comes from retaining the completed score (`lastScoredKey`) across sort toggles, not from background prewarming.

**How to apply:** In `EpisodesListViewModel`, keep all recommendation work — the candidate-set observation, the `$scoringRevision` observation, and scoring — gated behind `currentSortMethod == .recommendationScore`. Do not reintroduce background scoring on non-rec sorts. Retain `lastScoredKey` across teardown so re-selecting the sort is instant. `PodcastRecommendationScorer` prewarming is a separate decision — if revisiting it, treat it independently from the EpisodesListView change.
