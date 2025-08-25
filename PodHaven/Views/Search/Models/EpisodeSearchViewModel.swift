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
final class EpisodeSearchViewModel: PodcastQueueableModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.searchService) private var searchService
  @ObservationIgnored @DynamicInjected(\.sleeper) private var sleeper

  private static let log = Log.as(LogSubsystem.SearchView.episode)

  // MARK: - State Management

  @ObservationIgnored private var searchTask: Task<Void, Never>?
  var state: EpisodeSearchState = .idle

  var searchText = "" {
    didSet {
      if searchText != oldValue {
        scheduleSearch()
      }
    }
  }

  // MARK: - PodcastQueueableModel

  func getPodcastEpisode(_ episode: UnsavedPodcastEpisode) async throws -> PodcastEpisode {
    try await repo.upsertPodcastEpisode(episode)
  }

  // MARK: - Searching

  private var debounceMilliseconds: Int { 500 }

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
      let unsavedPodcastEpisodes = try await performSearch(with: trimmedText)
      guard !Task.isCancelled else { return }

      state = .loaded(unsavedPodcastEpisodes)
    } catch {
      guard !Task.isCancelled else { return }

      Self.log.error(error)
      state = .error(ErrorKit.coreMessage(for: error))
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
