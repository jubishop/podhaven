// Copyright Justin Bishop, 2025

import Foundation

@Observable @MainActor class ResultsViewModel {
  // MARK: - Data

  private let searchResult: PodcastSearchResult
  let unsavedPodcasts: [UnsavedPodcast]

  var searchText: String { searchResult.searchText }
  var result: PodcastResultConvertible? { searchResult.result }

  // MARK: - Initialization

  init(searchResult: PodcastSearchResult) {
    self.searchResult = searchResult
    if let result = searchResult.result {
      unsavedPodcasts = result.convertibleFeeds.compactMap { try? $0.toUnsavedPodcast() }
    } else {
      unsavedPodcasts = []
    }
  }
}
