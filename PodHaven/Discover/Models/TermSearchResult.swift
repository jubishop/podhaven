// Copyright Justin Bishop, 2025

import Foundation

struct TermSearchResult: PodcastSearchResult {
  let searchText: String
  let termResult: TermResult?
  
  var result: PodcastResultConvertible? { termResult }

  init(searchText: String = "", termResult: TermResult? = nil) {
    self.searchText = searchText
    self.termResult = termResult
  }
}
