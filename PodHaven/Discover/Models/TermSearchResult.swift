// Copyright Justin Bishop, 2025

import Foundation

struct TermSearchResult {
  let searchedText: String
  let termResult: TermResult?

  init(searchedText: String = "", termResult: TermResult? = nil) {
    self.searchedText = searchedText
    self.termResult = termResult
  }
}
