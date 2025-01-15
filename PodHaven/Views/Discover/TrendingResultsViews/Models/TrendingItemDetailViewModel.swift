// Copyright Justin Bishop, 2025

import Foundation

@Observable @MainActor class TrendingItemDetailViewModel {
  let category: String
  let feedResult: TrendingResult.FeedResult

  init(category: String, feedResult: TrendingResult.FeedResult) {
    self.category = category
    self.feedResult = feedResult
  }
}
