// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
final class PodcastSearchViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.searchService) private var searchService
  @ObservationIgnored @DynamicInjected(\.sleeper) private var sleeper

  private static let log = Log.as(LogSubsystem.SearchView.podcast)

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

  @ObservationIgnored private var searchTask: Task<Void, Never>?
  @ObservationIgnored private var observationTask: Task<Void, Never>?

  var podcasts: IdentifiedArray<FeedURL, any PodcastDisplayable> = IdentifiedArray(
    id: \.feedURL
  )

  enum PodcastSearchState {
    case idle
    case loading
    case loaded
    case error(String)
  }
  var state: PodcastSearchState = .idle

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
      let unsavedPodcasts = try await performSearch(with: trimmedText)
      guard !Task.isCancelled else { return }

      podcasts = IdentifiedArray(
        uniqueElements: unsavedPodcasts.map { $0 as any PodcastDisplayable },
        id: \.feedURL
      )
      state = .loaded
      startObservingPodcasts()
    } catch {
      guard !Task.isCancelled else { return }

      Self.log.error(error)
      state = .error(ErrorKit.coreMessage(for: error))
    }
  }

  func performSearch(with searchText: String) async throws -> IdentifiedArray<
    FeedURL, UnsavedPodcast
  > {
    let convertibleFeeds: [any FeedResultConvertible]

    switch selectedMode {
    case .allFields:
      let result = try await searchService.searchByTerm(searchText)
      convertibleFeeds = result.convertibleFeeds
    case .titlesOnly:
      let result = try await searchService.searchByTitle(searchText)
      convertibleFeeds = result.convertibleFeeds
    }

    return IdentifiedArray(
      uniqueElements: convertibleFeeds.compactMap { try? $0.toUnsavedPodcast() },
      id: \.feedURL
    )
  }

  // MARK: - Podcast Observation

  private func startObservingPodcasts() {
    // Cancel any existing observation task
    observationTask?.cancel()

    // Get the current feedURLs to observe
    let feedURLs = Array(podcasts.ids)

    observationTask = Task { [weak self] in
      guard let self else { return }

      Self.log.debug("Starting observation for \(feedURLs.count) podcasts")

      do {
        for try await existingPodcasts in self.observatory.podcasts(feedURLs) {
          try Task.checkCancellation()
          Self.log.debug(
            """
            Updating observed podcasts:
              \(existingPodcasts.map(\.toString).joined(separator: "\n  "))
            """
          )
          for existingPodcast in existingPodcasts {
            podcasts[id: existingPodcast.feedURL] = existingPodcast
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
