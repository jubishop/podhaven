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

  var podcastEpisodes: IdentifiedArray<MediaURL, any EpisodeDisplayable> =
    IdentifiedArray(id: \.mediaURL)

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

  // MARK: - ManagingEpisodesModel

  func getPodcastEpisode(_ episode: any EpisodeDisplayable) async throws -> PodcastEpisode {
    if let unsavedPodcastEpisode = episode as? UnsavedPodcastEpisode {
      return try await repo.upsertPodcastEpisode(unsavedPodcastEpisode)
    } else if let podcastEpisode = episode as? PodcastEpisode {
      return podcastEpisode
    } else {
      Assert.fatal("Unsupported episode type: \(type(of: episode))")
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
        id: \.mediaURL
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
    MediaURL, UnsavedPodcastEpisode
  > {
    let result = try await searchService.searchByPerson(searchText)
    return result.toPodcastEpisodeArray()
  }

  // MARK: - Episode Observation

  private func startObservingEpisodes() {
    // Cancel any existing observation task
    observationTask?.cancel()

    // Get the current mediaURLs to observe
    let mediaURLs = Array(podcastEpisodes.ids)

    observationTask = Task { [weak self] in
      guard let self else { return }

      do {
        for try await databaseEpisodes in self.observatory.podcastEpisodesByMediaURLs(mediaURLs) {
          try Task.checkCancellation()

          // Swap out any episodes that exist in the database
          for databaseEpisode in databaseEpisodes {
            self.podcastEpisodes[id: databaseEpisode.mediaURL] = databaseEpisode
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
