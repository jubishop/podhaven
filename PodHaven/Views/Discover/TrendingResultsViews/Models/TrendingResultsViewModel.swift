// Copyright Justin Bishop, 2025

import Foundation

@Observable @MainActor class TrendingResultsViewModel {
  let category: String
  let trendingResult: TrendingResult?
  let unsavedPodcasts: [UnsavedPodcast] = []

  init(category: String, trendingResult: TrendingResult?) {
    self.category = category
    self.trendingResult = trendingResult
    if let trendingResult = trendingResult {
      unsavedPodcasts = trendingResult.feeds.compactMap { try? $0.toUnsavedPodcast()}
    }
  }
}
