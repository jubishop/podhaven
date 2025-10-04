// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import SwiftUI
import Tagged

extension Container {
  @MainActor var searchViewModel: Factory<SearchViewModel> {
    Factory(self) { @MainActor in SearchViewModel() }.scope(.cached)
  }
}

@Observable @MainActor
final class SearchViewModel {
  @ObservationIgnored @DynamicInjected(\.searchService) private var searchService
  @ObservationIgnored @DynamicInjected(\.sleeper) private var sleeper

  private static let log = Log.as(LogSubsystem.SearchView.main)

  // MARK: - Configuration

  private static let debounceDuration: Duration = .milliseconds(350)

  fileprivate struct TrendingConfiguration: Identifiable, Equatable {
    var id: TrendingSectionID { TrendingSectionID(icon.text) }
    let genreID: Int?
    let icon: AppIcon
  }
  private static let trendingConfigurations: [TrendingConfiguration] = [
    .init(genreID: nil, icon: .trendingTop),
    .init(genreID: 1321, icon: .trendingBusiness),
    .init(genreID: 1303, icon: .trendingComedy),
    .init(genreID: 1304, icon: .trendingEducation),
    .init(genreID: 1512, icon: .trendingHealth),
    .init(genreID: 1462, icon: .trendingHistory),
    .init(genreID: 1305, icon: .trendingKids),
    .init(genreID: 1489, icon: .trendingNews),
    .init(genreID: 1533, icon: .trendingScience),
    .init(genreID: 1545, icon: .trendingSports),
    .init(genreID: 1318, icon: .trendingTechnology),
    .init(genreID: 1488, icon: .trendingTrueCrime),
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

  var searchResults: [UnsavedPodcast] = []

  enum TrendingState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
  }
  var trendingState: TrendingState = .idle

  struct TrendingSection: Identifiable, Equatable {
    private let configuration: TrendingConfiguration

    let podcasts: [UnsavedPodcast]

    fileprivate init(configuration: TrendingConfiguration, podcasts: [UnsavedPodcast]) {
      self.configuration = configuration
      self.podcasts = podcasts
    }

    var id: TrendingSectionID { configuration.id }
    var icon: AppIcon { configuration.icon }
    var title: String { configuration.icon.text }
  }
  var trendingSections: [TrendingSection] = []

  typealias TrendingSectionID = Tagged<SearchViewModel, String>
  var currentTrendingSectionID: TrendingSectionID?

  var isShowingSearchResults: Bool {
    !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var selectedTrendingSection: TrendingSection? {
    if let currentTrendingSectionID,
      let matched = trendingSections.first(where: { $0.id == currentTrendingSectionID })
    {
      return matched
    }
    return trendingSections.first
  }

  // MARK: - Internal State

  @ObservationIgnored private var searchTask: Task<Void, Never>?
  @ObservationIgnored private var trendingTask: Task<Void, Never>?

  // MARK: - Initialization

  func execute() {
    loadTrendingIfNeeded()
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
          self.currentTrendingSectionID == nil
            || !sections.contains(where: { $0.id == self.currentTrendingSectionID })
        {
          self.currentTrendingSectionID = first.id
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
    var sectionMap: [TrendingSectionID: TrendingSection] = [:]

    try await withThrowingTaskGroup(of: TrendingSection?.self) { group in
      for configuration in configurations {
        group.addTask { [weak self] in
          guard let self else { return nil }

          do {
            let results = try await searchService.topPodcasts(
              genreID: configuration.genreID,
              limit: 48
            )
            try Task.checkCancellation()
            let podcasts = Array(results)
            guard !podcasts.isEmpty else { return nil }
            return TrendingSection(
              configuration: configuration,
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

  func selectTrendingSection(_ trendingSectionID: TrendingSectionID) {
    guard currentTrendingSectionID != trendingSectionID else { return }
    currentTrendingSectionID = trendingSectionID
  }

  // MARK: - Searching

  private func scheduleSearch() {
    searchTask?.cancel()

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
      let unsavedResults = try await searchService.searchedPodcasts(matching: term, limit: 48)
      try Task.checkCancellation()

      searchResults = Array(unsavedResults)
      searchState = .loaded
    } catch {
      guard !Task.isCancelled else { return }
      Self.log.error(error)
      searchState = .error(ErrorKit.coreMessage(for: error))
      searchResults.removeAll()
    }
  }

  // MARK: - Disappear

  func disappear() {
    Self.log.debug("disappear: executing")

    searchTask?.cancel()
    trendingTask?.cancel()
  }
}
