// Copyright Justin Bishop, 2025

import Foundation

struct TitleSearchResult {
  let searchedText: String
  let titleResult: TitleResult?

  init(searchedText: String = "", titleResult: TitleResult? = nil) {
    self.searchedText = searchedText
    self.titleResult = titleResult
  }
}
