// Copyright Justin Bishop, 2025

import Foundation

@Observable @MainActor class TrendingResultsViewModel {
  let category: String
  let trendingResult: TrendingResult?

  init(category: String, trendingResult: TrendingResult?) {
    self.category = category
    self.trendingResult = trendingResult
  }
}
