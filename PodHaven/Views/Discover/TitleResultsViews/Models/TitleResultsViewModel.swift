// Copyright Justin Bishop, 2025

import Foundation

@Observable @MainActor class TitleResultsViewModel {
  private let searchResult: TitleSearchResult
  let unsavedPodcasts: [UnsavedPodcast]
  
  var searchText: String { searchResult.searchedText }
  var titleResult: TitleResult? { searchResult.titleResult }
  
  init(searchResult: TitleSearchResult) {
    self.searchResult = searchResult
    if let titleResult = searchResult.titleResult {
      unsavedPodcasts = titleResult.feeds.compactMap { try? $0.toUnsavedPodcast() }
    } else {
      unsavedPodcasts = []
    }
  }
}
