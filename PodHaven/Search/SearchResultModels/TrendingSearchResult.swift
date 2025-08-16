// Copyright Justin Bishop, 2025

import Foundation

struct TrendingSearchResult: Hashable {
  let category: String
  let result: any PodcastResultConvertible

  init(category: String, result: any PodcastResultConvertible) {
    self.category = category
    self.result = result
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(category)
    hasher.combine(result)
  }

  static func == (lhs: TrendingSearchResult, rhs: TrendingSearchResult) -> Bool {
    lhs.category == rhs.category && lhs.result.id == rhs.result.id
  }
}
