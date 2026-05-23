// Copyright Justin Bishop, 2026

import Foundation

// Surface `PodcastRecommendationScorer` needs from the view model that owns it.
// The scorer reads live state, the episode list, and the active sort
// selection, and writes the list's sort/filter closures back.
@MainActor protocol RecommendationScoringHost: AnyObject {
  var state: PodcastDetailState { get }
  var episodeList: PowerList<ListedEpisode> { get }
  var currentSortMethod: PodcastDetailViewModel.SortMethod { get }
}
