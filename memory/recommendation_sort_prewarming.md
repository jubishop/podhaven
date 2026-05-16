---
name: recommendation-sort-prewarming
description: Preserve intentional recommendation-score prewarming for snappy sort toggles.
type: feedback
---

Pre-warming recommendation-score sorting on PodcastDetailView and EpisodesListView is intentional.

**Why:** The user wants recommendation scores computed before the recommendation-score sort is selected so switching to that sort feels snappy.

**How to apply:** When fixing performance or fan-out issues in `PodcastDetailViewModel`, `EpisodesListViewModel`, or `RecommendationEngine.contextRevision` handling, keep bounded/coalesced prewarming. Do not simply gate all recommendation-score computation behind `currentSortMethod == .recommendationScore`; apply UI sorting/filtering only when selected, but allow background score computation/cache refresh ahead of selection.
