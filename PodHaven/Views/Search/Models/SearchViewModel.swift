// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging
import SwiftUI
import Tagged

@Observable @MainActor final class SearchViewModel {
  @ObservationIgnored @DynamicInjected(\.iTunesService) private var iTunesService
  @ObservationIgnored @DynamicInjected(\.sleeper) private var sleeper
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory

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

  @Observable @MainActor final class TrendingSection: Hashable, Identifiable {
    let genreID: Int?
    let icon: AppIcon

    fileprivate(set) var state: LoadingState = .idle
    fileprivate(set) var podcasts: IdentifiedArrayOf<DisplayedPodcast> = []

    fileprivate var task: Task<Void, Never>? = nil

    init(genreID: Int?, icon: AppIcon) {
      self.genreID = genreID
      self.icon = icon
    }

    var title: String { icon.text }

    // MARK: - Hashable / Identifiable

    nonisolated var id: AppIcon { icon }

    nonisolated static func == (lhs: TrendingSection, rhs: TrendingSection) -> Bool {
      lhs.genreID == rhs.genreID && lhs.icon == rhs.icon
    }

    nonisolated func hash(into hasher: inout Hasher) {
      hasher.combine(genreID)
      hasher.combine(icon)
    }
  }
  let trendingSections: [TrendingSection]

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
  var searchResults: IdentifiedArrayOf<DisplayedPodcast> = []
  var isShowingSearchResults: Bool { !trimmedSearchText.isEmpty }

  @ObservationIgnored private var searchTask: Task<Void, Never>?
  @ObservationIgnored private var podcastObservationTask: Task<Void, Never>?

  // MARK: - Initialization

  init() {
    let topTrendingSection = TrendingSection(genreID: nil, icon: .trendingTop)
    currentTrendingSection = topTrendingSection
    trendingSections = [
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
  }

  func execute() {
    Self.log.debug("execute: executing")
    selectTrendingSection(currentTrendingSection)
  }

  // MARK: - Trending

  func selectTrendingSection(_ trendingSection: TrendingSection) {
    currentTrendingSection = trendingSection
    observeCurrentDisplay()
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

      await executeTrendingSectionFetch(trendingSection)

      trendingSection.task = nil
      observeCurrentDisplay()
    }

    trendingSection.task = task
    return task
  }

  private func executeTrendingSectionFetch(_ trendingSection: TrendingSection) async {
    do {
      let podcasts = try await iTunesService.topPodcasts(
        genreID: trendingSection.genreID,
        limit: Self.trendingLimit
      )
      try Task.checkCancellation()

      if podcasts.isEmpty {
        trendingSection.podcasts = []
        trendingSection.state = .error("No podcasts available in this category right now.")
      } else {
        trendingSection.podcasts = IdentifiedArray(
          podcasts.map(DisplayedPodcast.init),
          uniquingIDsWith: { _, new in new }
        )
        trendingSection.state = .loaded
      }
    } catch {
      Self.log.error(error, mundane: .trace)
      guard !Task.isCancelled else { return }

      trendingSection.podcasts = []
      trendingSection.state = .error(ErrorKit.coreMessage(for: error))
    }
  }

  // MARK: - Searching

  func refreshSearch() async {
    await performSearch(debounce: false).value
  }

  @discardableResult
  private func performSearch(debounce: Bool) -> Task<Void, Never> {
    searchTask?.cancel()
    searchTask = nil

    let task = Task { [weak self, trimmedSearchText] in
      guard let self else { return }

      guard isShowingSearchResults else {
        searchState = .idle
        searchResults = []
        observeCurrentDisplay()
        return
      }

      if debounce {
        try? await sleeper.sleep(for: Self.debounceDuration)
        guard !Task.isCancelled else { return }
      }

      await executeSearch(for: trimmedSearchText)

      observeCurrentDisplay()
    }

    searchTask = task
    return task
  }

  private func executeSearch(for term: String) async {
    searchState = .loading

    do {
      let unsavedResults = try await iTunesService.searchedPodcasts(
        matching: term,
        limit: Self.searchLimit
      )
      try Task.checkCancellation()
      guard term == trimmedSearchText else { return }

      searchResults = IdentifiedArray(
        unsavedResults.map(DisplayedPodcast.init),
        uniquingIDsWith: { _, new in new }
      )
      searchState = .loaded
    } catch {
      Self.log.error(error, mundane: .trace)
      guard !Task.isCancelled else { return }

      searchResults = []
      searchState = .error(ErrorKit.coreMessage(for: error))
    }
  }

  // MARK: - Observations

  private func observeCurrentDisplay() {
    if isShowingSearchResults {
      restartObservationForSearchResults()
    } else {
      restartObservationForTrendingSection(currentTrendingSection)
    }
  }

  private func restartObservationForSearchResults() {
    Self.log.debug(
      """
      restartObservationForSearchResults: \(searchText)
        \(searchResults.count) search results.
      """
    )

    restartObservation(feedURLs: searchResults.map(\.feedURL)) { [weak self] podcasts in
      guard let self else { return }

      Self.log.debug("Now updating \(podcasts.count) podcasts for \(searchText)")
      for podcast in podcasts where searchResults[id: podcast.feedURL] != nil {
        searchResults[id: podcast.feedURL] = DisplayedPodcast(podcast)
      }
    }
  }

  private func restartObservationForTrendingSection(_ trendingSection: TrendingSection) {
    Self.log.debug(
      """
      restartObservationForTrendingSection: \(trendingSection.title)
        \(trendingSection.podcasts.count) trending podcasts.
      """
    )

    restartObservation(feedURLs: trendingSection.podcasts.map(\.feedURL)) { podcasts in
      Self.log.debug("Now updating \(podcasts.count) podcasts for \(trendingSection.title)")
      for podcast in podcasts where trendingSection.podcasts[id: podcast.feedURL] != nil {
        trendingSection.podcasts[id: podcast.feedURL] = DisplayedPodcast(podcast)
      }
    }
  }

  private func restartObservation(
    feedURLs: [FeedURL],
    update: @escaping ([Podcast]) -> Void
  ) {
    podcastObservationTask?.cancel()

    guard !feedURLs.isEmpty else {
      podcastObservationTask = nil
      return
    }

    podcastObservationTask = Task { [weak self] in
      guard let self else { return }

      do {
        for try await podcasts in observatory.podcasts(feedURLs) {
          try Task.checkCancellation()
          Self.log.debug("Observed \(podcasts.count) new podcasts")
          update(podcasts)
        }
      } catch {
        guard ErrorKit.isRemarkable(error) else { return }
        Self.log.error(error, mundane: .trace)
      }
    }
  }

  // MARK: - Disappear

  func disappear() {
    Self.log.debug("disappear: executing")

    searchTask?.cancel()
    searchTask = nil
    podcastObservationTask?.cancel()
    podcastObservationTask = nil
    for trendingSection in trendingSections {
      trendingSection.task?.cancel()
      trendingSection.task = nil
    }
    searchText = ""
  }
}
