// Copyright Justin Bishop, 2025

import Foundation

@Observable @MainActor class AllFieldsResultsViewModel {
  private let searchResult: TermSearchResult
  let unsavedPodcasts: [UnsavedPodcast]
  
  var searchText: String { searchResult.searchedText }
  var termResult: TermResult? { searchResult.termResult }
  
  init(searchResult: TermSearchResult) {
    self.searchResult = searchResult
    if let termResult = searchResult.termResult {
      unsavedPodcasts = termResult.feeds.compactMap { try? $0.toUnsavedPodcast() }
    } else {
      unsavedPodcasts = []
    }
  }
}
