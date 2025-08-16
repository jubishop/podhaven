// Copyright Justin Bishop, 2025

import Foundation

@Observable @MainActor class ResultsViewModel {
  // MARK: - Data

  private let searchResult: PodcastSearchResult
  let title: String
  let unsavedPodcasts: [UnsavedPodcast]

  var searchText: String { searchResult.searchText }
  var result: any PodcastResultConvertible { searchResult.result }

  // MARK: - Initialization

  init(title: String, searchResult: PodcastSearchResult) {
    self.title = title
    self.searchResult = searchResult
    unsavedPodcasts = searchResult.result.convertibleFeeds.compactMap { try? $0.toUnsavedPodcast() }
  }
}
