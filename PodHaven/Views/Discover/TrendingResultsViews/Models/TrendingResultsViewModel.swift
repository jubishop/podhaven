// Copyright Justin Bishop, 2025

import Foundation

@Observable @MainActor class TrendingResultsViewModel {
  // MARK: - Data

  private let searchResult: TrendingSearchResult
  let unsavedPodcasts: [UnsavedPodcast]

  var category: String { searchResult.searchedCategory }
  var trendingResult: TrendingResult? { searchResult.trendingResult }

  // MARK: - Initialization

  init(searchResult: TrendingSearchResult) {
    self.searchResult = searchResult
    if let trendingResult = searchResult.trendingResult {
      unsavedPodcasts = trendingResult.feeds.compactMap { try? $0.toUnsavedPodcast() }
    } else {
      unsavedPodcasts = []
    }
  }
}
