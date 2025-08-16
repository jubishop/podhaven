// Copyright Justin Bishop, 2025

import Foundation

struct PersonSearchResult {
  let searchText: String
  let personResult: PersonResult

  init(searchText: String, personResult: PersonResult) {
    self.searchText = searchText
    self.personResult = personResult
  }
}
