// Copyright Justin Bishop, 2025

import Foundation

@Observable @MainActor class TitleResultsViewModel {
  // MARK: - Data

  private let searchResult: TitleSearchResult
  let unsavedPodcasts: [UnsavedPodcast]

  var searchText: String { searchResult.searchedText }
  var titleResult: TitleResult? { searchResult.titleResult }

  // MARK: - Initialization

  init(searchResult: TitleSearchResult) {
    self.searchResult = searchResult
    if let titleResult = searchResult.titleResult {
      unsavedPodcasts = titleResult.feeds.compactMap { try? $0.toUnsavedPodcast() }
    } else {
      unsavedPodcasts = []
    }
  }
}
