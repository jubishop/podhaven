// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import SwiftUI

// MARK: - Search State

enum EpisodeSearchState {
  case idle
  case loading
  case loaded([UnsavedPodcastEpisode])
  case error(String)
}

@Observable @MainActor
final class EpisodeSearchViewModel {
  @ObservationIgnored @DynamicInjected(\.searchService) private var searchService
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.sleeper) private var sleeper

  // MARK: - State Management

  var state: EpisodeSearchState = .idle
  @ObservationIgnored var searchTask: Task<Void, Never>?

  var searchText = "" {
    didSet {
      if searchText != oldValue {
        scheduleSearch()
      }
    }
  }

  // MARK: - Searching

  private var debounceMilliseconds: Int { 500 }

  var episodes: [UnsavedPodcastEpisode] {
    switch state {
    case .loaded(let episodes):
      return episodes
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
      let episodes = try await performSearch(with: trimmedText)
      guard !Task.isCancelled else { return }

      state = .loaded(episodes)
    } catch {
      guard !Task.isCancelled else { return }

      state = .error(ErrorKit.message(for: error))
    }
  }

  func performSearch(with searchText: String) async throws -> [UnsavedPodcastEpisode] {
    let result = try await searchService.searchByPerson(searchText)
    return Array(result.toPodcastEpisodeArray())
  }

  // MARK: - Cleanup

  deinit {
    searchTask?.cancel()
  }
}
