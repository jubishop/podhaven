// Copyright Justin Bishop, 2025

import Foundation

@Observable @MainActor class PersonResultsViewModel {
  // MARK: - Data

  let title: String
  let searchResult: PersonSearchResult
  var searchText: String { searchResult.searchText }
  var personResult: PersonResult? { searchResult.personResult }

  // MARK: - Initialization

  init(title: String, searchResult: PersonSearchResult) {
    self.title = title
    self.searchResult = searchResult
  }
}
