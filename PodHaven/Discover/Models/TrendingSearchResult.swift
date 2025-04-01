// Copyright Justin Bishop, 2025

import Foundation

struct TrendingSearchResult: PodcastSearchResult {
  let searchCategory: String
  var trendingResult: TrendingResult?

  var searchText: String { searchCategory }
  var result: PodcastResultConvertible? { trendingResult }

  init(searchCategory: String = "", trendingResult: TrendingResult? = nil) {
    self.searchCategory = searchCategory
    self.trendingResult = trendingResult
  }
}
