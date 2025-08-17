// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import SwiftUI

@Observable @MainActor
final class TitleSearchViewModel: PodcastSearchViewableModel, SearchableModel {
  @ObservationIgnored @DynamicInjected(\.searchService) private var searchService

  // MARK: - PodcastSearchViewableModel Requirements

  let searchConfiguration = SearchConfiguration(
    navigationTitle: "Search by Title",
    idleTitle: "Search for podcasts by title",
    idleDescription: "Enter podcast titles to find exact or similar podcast matches.",
    searchPrompt: "Search podcast titles..."
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
    let result = try await searchService.searchByTitle(searchText)
    return result.convertibleFeeds.compactMap { try? $0.toUnsavedPodcast() }
  }

  // MARK: - SearchableModel Requirements

  @ObservationIgnored var searchTask: Task<Void, Never>?

  // MARK: - Cleanup

  deinit {
    searchTask?.cancel()
  }
}
