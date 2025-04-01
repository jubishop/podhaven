// Copyright Justin Bishop, 2025

import Foundation

@Observable
@MainActor
class PersonResultsViewModel {
  // MARK: - Data

  let searchResult: PersonSearchResult
  var searchText: String { searchResult.searchedText }
  var personResult: PersonResult? { searchResult.personResult }

  // MARK: - Initialization

  init(searchResult: PersonSearchResult) {
    self.searchResult = searchResult
  }
}
