// Copyright Justin Bishop, 2026

import Foundation

// Surface `PodcastRecommendationScorer` needs from the view model that owns it.
// Keeping it to four members documents the seam: the scorer reads live state
// and the episode list, and writes the list's sort/filter closures back.
@MainActor protocol RecommendationScoringHost: AnyObject {
  var state: PodcastDetailState { get }
  var episodeList: PowerList<ListedEpisode> { get }
  var isSortingByRecommendationScore: Bool { get }
  var recommendationFallbackFilter: (@Sendable (ListedEpisode) -> Bool)? { get }
}
