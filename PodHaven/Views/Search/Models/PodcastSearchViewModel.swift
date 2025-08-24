// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import SwiftUI

// MARK: - Search State

enum PodcastSearchState {
  case idle
  case loading
  case loaded([UnsavedPodcast])
  case error(String)
}

@Observable @MainActor
final class PodcastSearchViewModel {
  @ObservationIgnored @DynamicInjected(\.searchService) private var searchService
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.sleeper) private var sleeper

  // MARK: - Search Mode Configuration

  enum SearchMode: CaseIterable {
    case allFields
    case titlesOnly

    var displayName: String {
      switch self {
      case .allFields: return "Search All Fields"
      case .titlesOnly: return "Search Titles"
      }
    }

    var searchPrompt: String {
      switch self {
      case .allFields: return "Search podcasts..."
      case .titlesOnly: return "Search podcast titles..."
      }
    }

    var idleDescription: String {
      switch self {
      case .allFields:
        return
          "Enter search terms to find podcasts that match keywords in their title, description, or content."
      case .titlesOnly:
        return "Enter podcast titles to find exact or similar podcast matches."
      }
    }
  }

  // MARK: - State Management

  var state: PodcastSearchState = .idle
  @ObservationIgnored var searchTask: Task<Void, Never>?

  var searchText = "" {
    didSet {
      if searchText != oldValue {
        scheduleSearch()
      }
    }
  }

  var selectedMode: SearchMode = .allFields {
    didSet {
      if selectedMode != oldValue {
        // Re-trigger search with new mode if we have search text
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          scheduleSearch()
        }
      }
    }
  }

  // MARK: - Searching

  private var debounceMilliseconds: Int { 500 }

  var podcasts: [UnsavedPodcast] {
    switch state {
    case .loaded(let podcasts):
      return podcasts
    default:
      return []
    }
  }

  func scheduleSearch() {
    searchTask?.cancel()

    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      state = .idle
      return
    }

    searchTask = Task { [weak self] in
      guard let self else { return }
      try? await sleeper.sleep(for: .milliseconds(self.debounceMilliseconds))
      guard !Task.isCancelled else { return }

      await self.executeSearch()
    }
  }

  private func executeSearch() async {
    let trimmedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else {
      state = .idle
      return
    }

    state = .loading

    do {
      let unsavedPodcasts = try await performSearch(with: trimmedText)
      guard !Task.isCancelled else { return }

      state = .loaded(unsavedPodcasts)
    } catch {
      guard !Task.isCancelled else { return }

      state = .error(ErrorKit.message(for: error))
    }
  }

  func performSearch(with searchText: String) async throws -> [UnsavedPodcast] {
    let convertibleFeeds: [any FeedResultConvertible]

    switch selectedMode {
    case .allFields:
      let result = try await searchService.searchByTerm(searchText)
      convertibleFeeds = result.convertibleFeeds
    case .titlesOnly:
      let result = try await searchService.searchByTitle(searchText)
      convertibleFeeds = result.convertibleFeeds
    }

    return convertibleFeeds.compactMap { try? $0.toUnsavedPodcast() }
  }

  // MARK: - Cleanup

  deinit {
    searchTask?.cancel()
  }
}
