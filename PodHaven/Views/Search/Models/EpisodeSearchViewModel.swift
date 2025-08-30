// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
final class EpisodeSearchViewModel: ManagingEpisodesModel {
  typealias EpisodeType = any EpisodeDisplayable

  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.searchService) private var searchService
  @ObservationIgnored @DynamicInjected(\.sleeper) private var sleeper

  private static let log = Log.as(LogSubsystem.SearchView.episode)

  // MARK: - State Management

  @ObservationIgnored private var searchTask: Task<Void, Never>?
  @ObservationIgnored private var observationTask: Task<Void, Never>?

  var podcastEpisodes: IdentifiedArray<MediaGUID, any EpisodeDisplayable> =
    IdentifiedArray(id: \.mediaGUID)

  enum EpisodeSearchState {
    case idle
    case loading
    case loaded
    case error(String)
  }
  var state: EpisodeSearchState = .idle

  var searchText = "" {
    didSet {
      if searchText != oldValue {
        scheduleSearch()
      }
    }
  }

  // MARK: - Searching

  private var debounceMilliseconds: Int { 500 }

  func scheduleSearch() {
    searchTask?.cancel()
    observationTask?.cancel()

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

      podcastEpisodes = IdentifiedArray(
        uniqueElements: unsavedPodcastEpisodes.map { $0 as any EpisodeDisplayable },
        id: \.mediaGUID
      )
      state = .loaded
      startObservingEpisodes()
    } catch {
      guard !Task.isCancelled else { return }

      Self.log.error(error)
      state = .error(ErrorKit.coreMessage(for: error))
    }
  }

  func performSearch(with searchText: String) async throws -> IdentifiedArray<
    MediaGUID, UnsavedPodcastEpisode
  > {
    let result = try await searchService.searchByPerson(searchText)
    return result.toPodcastEpisodeArray()
  }

  // MARK: - Episode Observation

  private func startObservingEpisodes() {
    // Cancel any existing observation task
    observationTask?.cancel()

    // Get the current mediaGUIDs to observe
    let mediaGUIDs = Array(podcastEpisodes.ids)

    observationTask = Task { [weak self] in
      guard let self else { return }

      do {
        for try await databaseEpisodes in self.observatory.podcastEpisodes(mediaGUIDs) {
          try Task.checkCancellation()

          // Swap out any episodes that exist in the database
          for databaseEpisode in databaseEpisodes {
            self.podcastEpisodes[id: databaseEpisode.mediaGUID] = databaseEpisode
          }
        }
      } catch {
        Self.log.error(error)
      }
    }
  }

  // MARK: - Cleanup

  deinit {
    searchTask?.cancel()
    observationTask?.cancel()
  }
}
