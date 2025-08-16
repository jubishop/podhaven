// Copyright Justin Bishop, 2025

import Foundation

struct PodcastSearchResult {
  let searchText: String
  let result: any PodcastResultConvertible

  init(searchText: String, result: any PodcastResultConvertible) {
    self.searchText = searchText
    self.result = result
  }
}
