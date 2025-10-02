// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging

extension Container {
  @MainActor var searchTabViewModel: Factory<SearchTabViewModel> {
    Factory(self) { @MainActor in SearchTabViewModel() }.scope(.cached)
  }
}

@Observable @MainActor
final class SearchTabViewModel {
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.searchService) private var searchService
  @ObservationIgnored @DynamicInjected(\.sleeper) private var sleeper

  private static let log = Log.as(LogSubsystem.SearchView.main)

  // MARK: - Configuration

  private static let debounceDuration: Duration = .milliseconds(350)

  private static let trendingConfigurations: [TrendingConfiguration] = [
    .init(id: "top", title: "Top Podcasts", genreID: nil, fetchLimit: 50, displayLimit: 12),
    .init(id: "news", title: "News", genreID: 1489, fetchLimit: 50, displayLimit: 12),
    .init(id: "trueCrime", title: "True Crime", genreID: 1488, fetchLimit: 50, displayLimit: 12),
    .init(id: "comedy", title: "Comedy", genreID: 1303, fetchLimit: 50, displayLimit: 12),
    .init(id: "business", title: "Business", genreID: 1321, fetchLimit: 50, displayLimit: 12),
    .init(id: "technology", title: "Technology", genreID: 1318, fetchLimit: 50, displayLimit: 12),
  ]

  // MARK: - Published State

  var searchText: String = "" {
    didSet {
      if searchText != oldValue {
        scheduleSearch()
      }
    }
  }

  enum SearchState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
  }
  var searchState: SearchState = .idle

  var searchResults: IdentifiedArray<FeedURL, any PodcastDisplayable> = IdentifiedArray(
    uniqueElements: [],
    id: \.feedURL
  )

  enum TrendingState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
  }
  var trendingState: TrendingState = .idle
  var trendingSections: [TrendingSection] = []
  var selectedTrendingID: String? = trendingConfigurations.first?.id

  var isShowingSearchResults: Bool {
    !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var selectedTrendingSection: TrendingSection? {
    if let selectedTrendingID,
      let matched = trendingSections.first(where: { $0.id == selectedTrendingID })
    {
      return matched
    }
    return trendingSections.first
  }

  // MARK: - Internal State

  @ObservationIgnored private var searchTask: Task<Void, Never>?
  @ObservationIgnored private var observationTask: Task<Void, Never>?
  @ObservationIgnored private var trendingTask: Task<Void, Never>?

  deinit {
    searchTask?.cancel()
    observationTask?.cancel()
    trendingTask?.cancel()
  }

  // MARK: - Trending

  func loadTrendingIfNeeded() {
    guard case .idle = trendingState else { return }
    trendingState = .loading

    trendingTask?.cancel()
    trendingTask = Task { @MainActor [weak self] in
      guard let self else { return }

      do {
        let sections = try await self.fetchTrendingSections()
        try Task.checkCancellation()
        self.trendingSections = sections
        if let first = sections.first,
          self.selectedTrendingID == nil
            || !sections.contains(where: { $0.id == self.selectedTrendingID })
        {
          self.selectedTrendingID = first.id
        }
        self.trendingState = .loaded
      } catch {
        guard !Task.isCancelled else { return }
        Self.log.error(error)
        self.trendingState = .error(ErrorKit.message(for: error))
      }
    }
  }

  private func fetchTrendingSections() async throws -> [TrendingSection] {
    let configurations = Self.trendingConfigurations
    var sectionMap: [String: TrendingSection] = [:]

    try await withThrowingTaskGroup(of: TrendingSection?.self) { group in
      for configuration in configurations {
        group.addTask { [weak self] in
          guard let self else { return nil }

          do {
            let results = try await searchService.topPodcasts(
              genreID: configuration.genreID,
              limit: configuration.fetchLimit
            )
            try Task.checkCancellation()
            let podcasts = Array(results.prefix(configuration.displayLimit))
            guard !podcasts.isEmpty else { return nil }
            return TrendingSection(
              id: configuration.id,
              title: configuration.title,
              podcasts: podcasts
            )
          } catch {
            Log.as(LogSubsystem.SearchView.main).error(error)
            return nil
          }
        }
      }

      for try await section in group {
        if let section {
          sectionMap[section.id] = section
        }
      }
    }

    return configurations.compactMap { sectionMap[$0.id] }
  }

  func selectTrendingSection(_ id: String) {
    guard selectedTrendingID != id else { return }
    selectedTrendingID = id
  }

  // MARK: - Searching

  private func scheduleSearch() {
    searchTask?.cancel()
    observationTask?.cancel()

    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      searchState = .idle
      searchResults.removeAll()
      return
    }

    searchTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        try await self.sleeper.sleep(for: Self.debounceDuration)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      await self.executeSearch(for: trimmed)
    }
  }

  private func executeSearch(for term: String) async {
    searchState = .loading

    do {
      let unsavedResults = try await searchService.searchPodcasts(matching: term)
      try Task.checkCancellation()

      let displayable = IdentifiedArray<FeedURL, any PodcastDisplayable>(
        uniqueElements: Array(unsavedResults).map { $0 as any PodcastDisplayable },
        id: \.feedURL
      )

      searchResults = displayable
      searchState = .loaded
      startObservingPodcasts()
    } catch {
      guard !Task.isCancelled else { return }
      Self.log.error(error)
      searchState = .error(ErrorKit.coreMessage(for: error))
      searchResults.removeAll()
    }
  }

  private func startObservingPodcasts() {
    observationTask?.cancel()
    let feedURLs = Array(searchResults.ids)
    guard !feedURLs.isEmpty else { return }

    observationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        for try await podcasts in self.observatory.podcasts(feedURLs) {
          try Task.checkCancellation()
          for podcast in podcasts {
            self.searchResults[id: podcast.feedURL] = podcast
          }
        }
      } catch {
        Self.log.error(error)
      }
    }
  }

  // MARK: - Types

  struct TrendingSection: Identifiable, Equatable {
    let id: String
    let title: String
    let podcasts: [UnsavedPodcast]
  }

  private struct TrendingConfiguration: Equatable {
    let id: String
    let title: String
    let genreID: Int?
    let fetchLimit: Int
    let displayLimit: Int
  }
}
