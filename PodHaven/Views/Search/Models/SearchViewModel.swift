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
  private static let trendingLimit = 48
  private static let searchLimit = 48

  // MARK: - Internal State

  enum LoadingState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
  }

  // MARK: - Trending State

  struct TrendingSection {
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

    var title: String { icon.text }
  }

  let trendingSections: IdentifiedArray<String, TrendingSection>
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
  var trimmedSearchText: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

  var searchResults: [UnsavedPodcast] = []
  var isShowingSearchResults: Bool { !trimmedSearchText.isEmpty }

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
      ],
      id: \.title
    )
  }

  func execute() {
    loadTrendingSection(currentTrendingSection)
  }

  // MARK: - Trending

  func selectTrendingSection(_ trendingSection: TrendingSection) {
    currentTrendingSection = trendingSection
    loadTrendingSection(trendingSection)
  }

  func refreshCurrentTrendingSection() async {
    currentTrendingSection.task?.cancel()
    currentTrendingSection.task = nil

    currentTrendingSection.podcasts = []
    currentTrendingSection.state = .idle

    await executeTrendingSectionFetch(currentTrendingSection).value
  }

  private func loadTrendingSection(_ trendingSection: TrendingSection) {
    switch trendingSection.state {
    case .loaded, .loading:
      return
    default:
      break
    }

    executeTrendingSectionFetch(trendingSection)
  }

  @discardableResult
  private func executeTrendingSectionFetch(_ trendingSection: TrendingSection) -> Task<Void, Never>
  {
    var mutableSection = trendingSection
    mutableSection.state = .loading

    let task = Task { [weak self, trendingSection] in
      guard let self else { return }

      do {
        let podcasts = try await searchService.topPodcasts(
          genreID: trendingSection.genreID,
          limit: Self.trendingLimit
        )
        try Task.checkCancellation()

        if podcasts.isEmpty {
          mutableSection.podcasts = []
          mutableSection.state = .error("No podcasts available in this category right now.")
        } else {
          mutableSection.podcasts = podcasts
          mutableSection.state = .loaded
        }
      } catch {
        Self.log.error(error, mundane: .trace)
        guard !Task.isCancelled else { return }

        mutableSection.podcasts = []
        mutableSection.state = .error(ErrorKit.coreMessage(for: error))
      }

      mutableSection.task = nil
    }

    mutableSection.task = task
    return task
  }

  // MARK: - Searching

  private func scheduleSearch() {
    searchTask?.cancel()

    let trimmedSearchText = trimmedSearchText
    guard !trimmedSearchText.isEmpty else {
      searchState = .idle
      searchResults = []
      return
    }

    searchTask = Task { [weak self, trimmedSearchText] in
      guard let self else { return }

      try await sleeper.sleep(for: Self.debounceDuration)
      try Task.checkCancellation()

      await executeSearch(for: trimmedSearchText)
    }
  }

  private func executeSearch(for term: String) async {
    searchState = .loading

    do {
      let unsavedResults = try await searchService.searchedPodcasts(
        matching: term,
        limit: Self.searchLimit
      )
      try Task.checkCancellation()

      searchResults = unsavedResults
      searchState = .loaded
    } catch {
      Self.log.error(error, mundane: .trace)
      guard !Task.isCancelled else { return }

      searchResults = []
      searchState = .error(ErrorKit.coreMessage(for: error))
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
