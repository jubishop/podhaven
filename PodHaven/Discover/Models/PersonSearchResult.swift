// Copyright Justin Bishop, 2025

import Foundation

struct PersonSearchResult {
  let searchedText: String
  let personResult: PersonResult?

  init(searchedText: String = "", personResult: PersonResult? = nil) {
    self.searchedText = searchedText
    self.personResult = personResult
  }
}
