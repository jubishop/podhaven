// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
final class EpisodeSearchViewModel: ManagingEpisodes {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.navigation) private var navigation
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.searchService) private var searchService
  @ObservationIgnored @DynamicInjected(\.sleeper) private var sleeper

  private static let log = Log.as(LogSubsystem.SearchView.episode)

  // MARK: - State Management

  @ObservationIgnored private var searchTask: Task<Void, Never>?
  @ObservationIgnored private var observationTask: Task<Void, Never>?

  var episodes: IdentifiedArray<MediaGUID, any EpisodeDisplayable> = IdentifiedArray(
    id: \.mediaGUID
  )

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

  private var debounceMilliseconds: Int { 250 }

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

      episodes = IdentifiedArray(
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
    let mediaGUIDs = Array(episodes.ids)

    observationTask = Task { [weak self] in
      guard let self else { return }

      Self.log.debug("Starting observation for \(mediaGUIDs.count) episodes")

      do {
        for try await podcastEpisodes in self.observatory.podcastEpisodes(mediaGUIDs) {
          try Task.checkCancellation()
          Self.log.debug(
            """
            Updating observed episodes:
              \(podcastEpisodes.map(\.toString).joined(separator: "\n  "))
            """
          )
          for podcastEpisode in podcastEpisodes {
            episodes[id: podcastEpisode.mediaGUID] = podcastEpisode
          }
        }
      } catch {
        Self.log.error(error)
      }
    }
  }

  // MARK: - Cleanup

  func disappear() {
    Self.log.debug("disappear: executing")
    searchTask?.cancel()
    observationTask?.cancel()
  }
}
