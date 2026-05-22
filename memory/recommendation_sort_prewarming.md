---
name: recommendation-sort-prewarming
description: Recommendation-score sorting is computed on demand in both EpisodesListView and PodcastDetailView; nothing prewarms.
type: feedback
---

Recommendation-score sorting is computed **on demand** in both `EpisodesListViewModel` and `PodcastDetailViewModel`/`PodcastRecommendationScorer` — only while the `recommendationScore` sort is the selected one. Nothing is prewarmed in the background on other sorts.

**Why:** Issues #310 (EpisodesListView) and #311 (PodcastDetailView) — constant background scoring on every list display / tab switch was too costly and complex. The user accepts a one-time "Computing recommendations…" wait when first selecting the rec sort; snappiness on re-selection comes from retaining the completed score across sort toggles — re-selecting verifies the snapshot is unchanged and reuses the retained score without recomputing — not from background prewarming.

**How to apply:** Keep all recommendation work — the `$scoringRevision` observation, the candidate-set / state-change observation, and scoring itself — gated behind the rec sort being selected. Do not reintroduce background scoring on non-rec sorts. In `PodcastRecommendationScorer`, `applyRecommendationSort()` is the sole scoring entry point: it starts the `$scoringRevision` observation, `clearDisplay()`/`disappear()` tear it down, and `stateDidChange()` only rescores while `isSortingByRecommendationScore`. Retain the last computed score (`lastRecommendationScores` / `EpisodesListViewModel`'s `recommendationScoresState`) across teardown so re-selecting the sort skips rescoring when the snapshot still matches and shows the computing banner when it doesn't. A new scoring request cancels the in-flight pass and restarts (cancel-and-restart) — there is no debounce/coalescer. See [[podcast_detail_recommendation_storm]] and [[recommendation_engine_full_library_rescan]] for the storm history this removed.
