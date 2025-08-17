// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import SwiftUI

@Observable @MainActor
final class TermSearchViewModel: PodcastSearchViewableModel, SearchableModel {
  @ObservationIgnored @DynamicInjected(\.searchService) private var searchService

  // MARK: - PodcastSearchViewableModel Requirements

  let searchConfiguration = SearchConfiguration(
    navigationTitle: "Search by Term",
    idleTitle: "Search for podcasts by keyword",
    idleDescription:
      "Enter search terms to find podcasts that match keywords in their title, description, or content.",
    searchPrompt: "Search podcasts..."
  )

  var state: PodcastSearchState = .idle

  var searchText = "" {
    didSet {
      if searchText != oldValue {
        scheduleSearch()
      }
    }
  }

  func performSearch(with searchText: String) async throws -> [UnsavedPodcast] {
    let result = try await searchService.searchByTerm(searchText)
    return result.convertibleFeeds.compactMap { try? $0.toUnsavedPodcast() }
  }

  // MARK: - SearchableModel Requirements

  @ObservationIgnored var searchTask: Task<Void, Never>?

  // MARK: - Cleanup

  deinit {
    searchTask?.cancel()
  }
}
