// Copyright Justin Bishop, 2025

import Foundation

struct TitleSearchResult: PodcastSearchResult {
  let searchText: String
  let titleResult: TitleResult?

  var result: PodcastResultConvertible? { titleResult }

  init(searchText: String = "", titleResult: TitleResult? = nil) {
    self.searchText = searchText
    self.titleResult = titleResult
  }
}
