// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging
import SwiftUI
import Tagged

extension Container {
  @MainActor var searchViewModel: Factory<SearchViewModel> {
    Factory(self) { @MainActor in SearchViewModel() }.scope(.cached)
  }
}

@Observable @MainActor final class SearchViewModel {
  @ObservationIgnored @DynamicInjected(\.searchService) private var searchService
  @ObservationIgnored @DynamicInjected(\.sleeper) private var sleeper

  private static let log = Log.as(LogSubsystem.SearchView.main)

  // MARK: - Configuration

  private static let debounceDuration: Duration = .milliseconds(300)

  // MARK: - Internal State

  enum LoadingState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
  }

  // MARK: - Trending State

  typealias TrendingSectionID = Tagged<SearchViewModel, String>
  struct TrendingSection: Identifiable, Equatable {
    let genreID: Int?
    let icon: AppIcon

    fileprivate(set) var state: LoadingState
    fileprivate(set) var podcasts: [UnsavedPodcast]

    fileprivate var task: Task<Void, Never>? = nil

    fileprivate init(
      genreID: Int?,
      icon: AppIcon,
      state: LoadingState = .idle,
      podcasts: [UnsavedPodcast] = []
    ) {
      self.genreID = genreID
      self.icon = icon
      self.state = state
      self.podcasts = podcasts
    }

    var id: TrendingSectionID { TrendingSectionID(icon.text) }
    var title: String { icon.text }
  }

  let trendingSections: IdentifiedArrayOf<TrendingSection>
  private(set) var currentTrendingSection: TrendingSection

  // MARK: - Search State

  var searchState: LoadingState = .idle
  var searchText: String = "" {
    didSet {
      if searchText != oldValue {
        scheduleSearch()
      }
    }
  }

  var searchResults: [UnsavedPodcast] = []
  var isShowingSearchResults: Bool {
    !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  // MARK: - Internal State

  @ObservationIgnored private var searchTask: Task<Void, Error>?

  // MARK: - Initialization

  init() {
    let topTrendingSection = TrendingSection(genreID: nil, icon: .trendingTop)
    currentTrendingSection = topTrendingSection
    trendingSections = IdentifiedArray(
      uniqueElements: [
        topTrendingSection,
        TrendingSection(genreID: 1321, icon: .trendingBusiness),
        TrendingSection(genreID: 1303, icon: .trendingComedy),
        TrendingSection(genreID: 1304, icon: .trendingEducation),
        TrendingSection(genreID: 1512, icon: .trendingHealth),
        TrendingSection(genreID: 1462, icon: .trendingHistory),
        TrendingSection(genreID: 1305, icon: .trendingKids),
        TrendingSection(genreID: 1489, icon: .trendingNews),
        TrendingSection(genreID: 1533, icon: .trendingScience),
        TrendingSection(genreID: 1545, icon: .trendingSports),
        TrendingSection(genreID: 1318, icon: .trendingTechnology),
        TrendingSection(genreID: 1488, icon: .trendingTrueCrime),
      ]
    )
  }

  func execute() {
    loadTrendingSectionIfNeeded()
  }

  // MARK: - Trending

  func selectTrendingSection(_ trendingSectionID: TrendingSectionID) {
    guard let trendingSection = trendingSections[id: trendingSectionID] else { return }
    currentTrendingSection = trendingSection
    loadTrendingSectionIfNeeded()
  }

  func refreshCurrentTrendingSection() async {
    currentTrendingSection.task?.cancel()
    currentTrendingSection.task = nil

    currentTrendingSection.podcasts = []
    currentTrendingSection.state = .idle

    let task = startTrendingFetch(for: currentTrendingSection)
    await task.value
  }

  private func loadTrendingSectionIfNeeded() {
    switch currentTrendingSection.state {
    case .loaded, .loading:
      return
    default:
      break
    }

    startTrendingFetch(for: currentTrendingSection)
  }

  private func completeTrendingSectionLoad(
    trendingSection: TrendingSection,
    podcasts: [UnsavedPodcast],
    errorMessage: String?
  ) {
    var mutableSection = trendingSection
    if let errorMessage {
      mutableSection.podcasts = []
      mutableSection.state = .error(errorMessage)
    } else {
      mutableSection.podcasts = podcasts
      mutableSection.state = .loaded
    }

    mutableSection.task = nil
  }

  @discardableResult
  private func startTrendingFetch(for trendingSection: TrendingSection) -> Task<Void, Never> {
    var mutableSection = trendingSection
    mutableSection.state = .loading

    let task = Task { [weak self] in
      guard let self else { return }

      do {
        let results = try await self.searchService.topPodcasts(
          genreID: trendingSection.genreID,
          limit: 48
        )
        try Task.checkCancellation()

        let podcasts = Array(results)
        if podcasts.isEmpty {
          completeTrendingSectionLoad(
            trendingSection: trendingSection,
            podcasts: [],
            errorMessage: "No podcasts available in this category right now."
          )
        } else {
          completeTrendingSectionLoad(
            trendingSection: trendingSection,
            podcasts: podcasts,
            errorMessage: nil
          )
        }
      } catch {
        guard !Task.isCancelled else { return }
        Self.log.error(error)
        completeTrendingSectionLoad(
          trendingSection: trendingSection,
          podcasts: [],
          errorMessage: ErrorKit.coreMessage(for: error)
        )
      }
    }

    mutableSection.task = task
    return task
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

    searchTask = Task { [weak self] in
      guard let self else { return }

      try await self.sleeper.sleep(for: Self.debounceDuration)
      try Task.checkCancellation()

      await executeSearch(for: trimmed)
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
    for var trendingSection in trendingSections {
      trendingSection.task?.cancel()
      trendingSection.task = nil
    }
  }
}
