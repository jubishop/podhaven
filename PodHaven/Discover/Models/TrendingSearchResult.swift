// Copyright Justin Bishop, 2025

import Foundation

struct TrendingSearchResult {
  let searchedCategory: String
  var trendingResult: TrendingResult?

  init(searchedCategory: String = "", trendingResult: TrendingResult? = nil) {
    self.searchedCategory = searchedCategory
    self.trendingResult = trendingResult
  }
}
