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

  @Observable @MainActor final class TrendingSection {
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

    func disappear() {
      task?.cancel()
      task = nil
      podcasts = []
      state = .idle
    }
  }
  let trendingSections: IdentifiedArray<String, TrendingSection>

  private(set) var currentTrendingSection: TrendingSection

  // MARK: - Search State

  var searchState: LoadingState = .idle
  var searchText: String = "" {
    didSet {
      if searchText != oldValue {
        performSearch(debounce: true)
      }
    }
  }
  var trimmedSearchText: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
  var searchResults: [UnsavedPodcast] = []
  var isShowingSearchResults: Bool { !trimmedSearchText.isEmpty }

  @ObservationIgnored private var searchTask: Task<Void, Never>?

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

    await performTrendingSectionFetch(currentTrendingSection).value
  }

  private func loadTrendingSection(_ trendingSection: TrendingSection) {
    switch trendingSection.state {
    case .loaded, .loading:
      return
    default:
      break
    }

    performTrendingSectionFetch(trendingSection)
  }

  @discardableResult
  private func performTrendingSectionFetch(_ trendingSection: TrendingSection) -> Task<Void, Never>
  {
    trendingSection.state = .loading

    let task = Task { [weak self, trendingSection] in
      guard let self else { return }

      do {
        let podcasts = try await searchService.topPodcasts(
          genreID: trendingSection.genreID,
          limit: Self.trendingLimit
        )
        try Task.checkCancellation()

        if podcasts.isEmpty {
          trendingSection.podcasts = []
          trendingSection.state = .error("No podcasts available in this category right now.")
        } else {
          trendingSection.podcasts = podcasts
          trendingSection.state = .loaded
        }
      } catch {
        Self.log.error(error, mundane: .trace)
        guard !Task.isCancelled else { return }

        trendingSection.podcasts = []
        trendingSection.state = .error(ErrorKit.coreMessage(for: error))
      }

      trendingSection.task = nil
    }

    trendingSection.task = task
    return task
  }

  // MARK: - Searching

  @discardableResult
  func performSearch(debounce: Bool) -> Task<Void, Never> {
    searchTask?.cancel()
    searchTask = nil

    let task = Task { [weak self, trimmedSearchText] in
      guard let self else { return }

      guard !trimmedSearchText.isEmpty else {
        searchState = .idle
        searchResults = []
        return
      }

      if debounce {
        try? await sleeper.sleep(for: Self.debounceDuration)
        guard !Task.isCancelled else { return }
      }

      await executeSearch(for: trimmedSearchText)
    }

    searchTask = task
    return task
  }

  private func executeSearch(for term: String) async {
    searchState = .loading

    do {
      let unsavedResults = try await searchService.searchedPodcasts(
        matching: term,
        limit: Self.searchLimit
      )
      try Task.checkCancellation()
      guard term == trimmedSearchText else { return }

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

    searchText = ""
    for trendingSection in trendingSections {
      trendingSection.disappear()
    }
  }
}
