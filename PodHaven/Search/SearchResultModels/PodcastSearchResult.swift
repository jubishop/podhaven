// Copyright Justin Bishop, 2025

import Foundation

struct PodcastSearchResult: Hashable {
  let searchText: String
  let result: any PodcastResultConvertible

  init(searchText: String, result: any PodcastResultConvertible) {
    self.searchText = searchText
    self.result = result
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(searchText)
    hasher.combine(result)
  }

  static func == (lhs: PodcastSearchResult, rhs: PodcastSearchResult) -> Bool {
    lhs.searchText == rhs.searchText && lhs.result.id == rhs.result.id
  }
}
