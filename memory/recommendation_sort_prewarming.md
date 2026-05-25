---
name: recommendation-sort-prewarming
description: Recommendation-score sorting is computed on demand everywhere; background prewarming was removed and must not return.
type: feedback
---

Recommendation-score sorting runs **on demand** in both `EpisodesListViewModel`
and `PodcastDetailViewModel` — only while the `recommendationScore` sort is
selected. Nothing is prewarmed in the background.

**Why:** Issues #310 and #311 — constant background scoring on every list
display / tab switch was too costly and complex. Background prewarming was
removed from both surfaces; do not reintroduce it. Snappiness on re-selection
comes from retaining the last computed score across sort toggles, not from
prewarming.
