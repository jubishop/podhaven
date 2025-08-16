// Copyright Justin Bishop, 2025

import Foundation

struct PodcastSearchResult {
  let searchText: String
  let result: PodcastResultConvertible?

  init(searchText: String = "", result: PodcastResultConvertible? = nil) {
    self.searchText = searchText
    self.result = result
  }
}
