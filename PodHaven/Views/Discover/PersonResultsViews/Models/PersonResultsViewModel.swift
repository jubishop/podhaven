// Copyright Justin Bishop, 2025

import Foundation

@Observable @MainActor class PersonResultsViewModel {
  private let searchResult: PersonSearchResult
  let unsavedPodcastEpisodes: [UnsavedPodcastEpisode]

  var searchText: String { searchResult.searchedText }
  var personResult: PersonResult? { searchResult.personResult }

  init(searchResult: PersonSearchResult) {
    self.searchResult = searchResult
    if let personResult = searchResult.personResult {
      unsavedPodcastEpisodes = personResult.items.compactMap { try? $0.toUnsavedPodcastEpisode() }
    } else {
      unsavedPodcastEpisodes = []
    }
  }
}
