// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging
import SwiftUI
import Tagged

@Observable @MainActor class SearchViewModel: ManagingPodcasts, SelectablePodcastList {
  @ObservationIgnored @DynamicInjected(\.iTunesService) private var iTunesService
  @ObservationIgnored @DynamicInjected(\.sleeper) private var sleeper
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory

  private static let log = Log.as(LogSubsystem.SearchView.main)

  // MARK: - Configuration

  private static let debounceDuration: Duration = .milliseconds(300)
  private static let trendingLimit = 48
  private static let searchLimit = 48

  // MARK: - ManagingPodcasts

  func getOrCreatePodcast(_ displayedPodcast: DisplayedPodcast) async throws -> Podcast {
    try await displayedPodcast.getOrCreatePodcast()
  }

  // MARK: - SelectablePodcastList

  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }

  var podcastList = SelectableListUseCase<PodcastWithEpisodeMetadata<DisplayedPodcast>>(
    sortMethod: SortMethod.byServerOrder.sortMethod
  )

  func forEachSelectedPodcast(
    perform action: @escaping @Sendable (Podcast) async throws -> Void
  ) async {
    // Fetch all podcasts in parallel using a task group
    await withTaskGroup(of: Podcast?.self) { group in
      for selectedPodcastWithMetadata in selectedPodcastsWithMetadata {
        group.addTask {
          await Self.log.catch {
            try await selectedPodcastWithMetadata.podcast.getOrCreatePodcast()
          }
        }
      }

      // Process results as they complete
      for await podcast in group {
        if let podcast {
          await Self.log.catch {
            try await action(podcast)
          }
        }
      }
    }
  }

  enum SortMethod: String, CaseIterable, PodcastSortMethod {
    case byServerOrder
    case byTitle
    case byMostRecentEpisode
    case byEpisodeCount

    var appIcon: AppIcon {
      switch self {
      case .byServerOrder:
        return .sortByServerOrder
      case .byTitle:
        return .sortByTitle
      case .byMostRecentEpisode:
        return .sortByMostRecentEpisode
      case .byEpisodeCount:
        return .sortByEpisodeCount
      }
    }

    var sortMethod:
      (
        (PodcastWithEpisodeMetadata<DisplayedPodcast>, PodcastWithEpisodeMetadata<DisplayedPodcast>)
          -> Bool
      )?
    {
      switch self {
      case .byServerOrder:
        return nil
      case .byTitle:
        return { lhs, rhs in lhs.title < rhs.title }
      case .byMostRecentEpisode:
        return { lhs, rhs in
          let lhsDate = lhs.mostRecentEpisodeDate ?? Date.distantPast
          let rhsDate = rhs.mostRecentEpisodeDate ?? Date.distantPast
          return lhsDate > rhsDate
        }
      case .byEpisodeCount:
        return { lhs, rhs in lhs.episodeCount > rhs.episodeCount }
      }
    }
  }
  let allSortMethods = SortMethod.allCases

  private var _currentSortMethod: SortMethod = .byServerOrder
  var currentSortMethod: SortMethod {
    get { _currentSortMethod }
    set {
      _currentSortMethod = newValue
      podcastList.sortMethod = newValue.sortMethod
    }
  }

  // MARK: - State Management

  enum LoadingState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
  }

  // MARK: - Trending State

  @Observable @MainActor final class TrendingSection: Hashable, Identifiable {
    weak var owner: SearchViewModel?
    let genreID: Int?
    let icon: AppIcon

    fileprivate(set) var state: LoadingState = .idle
    fileprivate(set)
      var results: IdentifiedArrayOf<PodcastWithEpisodeMetadata<DisplayedPodcast>> = []
    {
      didSet {
        owner?.syncPodcastListToTrendingResults(self)
      }
    }

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
      let trimmedOldValue = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmedSearchText != trimmedOldValue else { return }

      if trimmedSearchText == "" {
        searchTask?.cancel()
        searchTask = nil
        searchedText = ""
        showTrendingSection(currentTrendingSection)
      } else {
        performSearch(debounce: true)
      }
    }
  }
  var trimmedSearchText: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
  var searchedText: String = ""
  var searchResults: IdentifiedArrayOf<PodcastWithEpisodeMetadata<DisplayedPodcast>> = [] {
    didSet {
      syncPodcastListToSearchResults()
    }
  }
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
    for section in trendingSections {
      section.owner = self
    }
    showTrendingSection(currentTrendingSection)
  }

  // MARK: - Trending

  func showTrendingSection(_ trendingSection: TrendingSection) {
    currentTrendingSection = trendingSection
    syncPodcastListToTrendingResults(trendingSection)
    if !loadTrendingSection(trendingSection) {
      restartObservationForTrendingSection(trendingSection)
    }
  }

  func refreshCurrentTrendingSection() async {
    currentTrendingSection.task?.cancel()
    currentTrendingSection.task = nil

    await performTrendingSectionFetch(currentTrendingSection).value
  }

  private func loadTrendingSection(_ trendingSection: TrendingSection) -> Bool {
    switch trendingSection.state {
    case .loaded, .loading:
      return false
    default:
      break
    }

    performTrendingSectionFetch(trendingSection)
    return true
  }

  @discardableResult
  private func performTrendingSectionFetch(_ trendingSection: TrendingSection) -> Task<Void, Never>
  {
    trendingSection.state = .loading

    let task = Task { [weak self, trendingSection] in
      guard let self else { return }

      if await executeTrendingSectionFetch(trendingSection) {
        restartObservationForTrendingSection(trendingSection)
      }

      trendingSection.task = nil
    }

    trendingSection.task = task
    return task
  }

  private func executeTrendingSectionFetch(_ trendingSection: TrendingSection) async -> Bool {
    do {
      let results = try await iTunesService.topPodcasts(
        genreID: trendingSection.genreID,
        limit: Self.trendingLimit
      )
      try Task.checkCancellation()

      if results.isEmpty {
        trendingSection.results = []
        trendingSection.state = .error("No podcasts available in this category right now.")
      } else {
        trendingSection.results = IdentifiedArray(
          results.map {
            PodcastWithEpisodeMetadata(
              podcast: DisplayedPodcast($0.podcast),
              episodeCount: $0.episodeCount,
              mostRecentEpisodeDate: $0.mostRecentEpisodeDate
            )
          },
          uniquingIDsWith: { _, new in new }
        )
        trendingSection.state = .loaded
      }
    } catch {
      Self.log.error(error, mundane: .trace)
      guard !Task.isCancelled else { return false }

      trendingSection.results = []
      trendingSection.state = .error(ErrorKit.coreMessage(for: error))
    }
    return true
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
      guard trimmedSearchText != "" else { return }

      if debounce {
        try? await sleeper.sleep(for: Self.debounceDuration)
        guard !Task.isCancelled else { return }
      }

      if await executeSearch(for: trimmedSearchText) {
        searchedText = trimmedSearchText
        restartObservationForSearchResults()
      }
    }

    searchTask = task
    return task
  }

  private func executeSearch(for term: String) async -> Bool {
    guard term != "" else { return false }

    searchState = .loading

    do {
      let results = try await iTunesService.searchedPodcasts(
        matching: term,
        limit: Self.searchLimit
      )
      try Task.checkCancellation()
      guard term == trimmedSearchText else { return false }

      searchResults = IdentifiedArray(
        results.map {
          PodcastWithEpisodeMetadata(
            podcast: DisplayedPodcast($0.podcast),
            episodeCount: $0.episodeCount,
            mostRecentEpisodeDate: $0.mostRecentEpisodeDate
          )
        },
        uniquingIDsWith: { _, new in new }
      )
      searchState = .loaded
    } catch {
      Self.log.error(error, mundane: .trace)
      guard !Task.isCancelled else { return false }

      searchResults = []
      searchState = .error(ErrorKit.coreMessage(for: error))
    }
    return true
  }

  // MARK: - Observation

  private func restartObservationForSearchResults() {
    guard isShowingSearchResults else { return }

    Self.log.debug(
      """
      restartObservationForSearchResults: \(searchText)
        \(searchResults.count) search results.
      """
    )

    restartObservation(feedURLs: Array(searchResults.ids)) { [weak self] podcasts in
      guard let self else { return }

      Self.log.debug("Now updating \(podcasts.count) podcasts for \(searchText)")
      for podcast in podcasts {
        if searchResults[id: podcast.feedURL] != nil {
          searchResults[id: podcast.feedURL] =
            PodcastWithEpisodeMetadata(
              podcast: DisplayedPodcast(podcast.podcast),
              episodeCount: podcast.episodeCount,
              mostRecentEpisodeDate: podcast.mostRecentEpisodeDate
            )
        } else {
          Self.log.notice("Observed podcast: \(podcast.toString) not showing in search?")
        }
      }

      syncPodcastListToSearchResults()
    }
  }

  private func restartObservationForTrendingSection(_ trendingSection: TrendingSection) {
    guard !isShowingSearchResults, trendingSection == currentTrendingSection else { return }

    Self.log.debug(
      """
      restartObservationForTrendingSection: \(trendingSection.title)
        \(trendingSection.results.count) trending podcasts.
      """
    )

    restartObservation(feedURLs: Array(trendingSection.results.ids)) {
      [weak self, trendingSection] podcasts in
      guard let self else { return }

      Self.log.debug("Now updating \(podcasts.count) podcasts for \(trendingSection.title)")
      for podcast in podcasts {
        if trendingSection.results[id: podcast.feedURL] != nil {
          trendingSection.results[id: podcast.feedURL] =
            PodcastWithEpisodeMetadata(
              podcast: DisplayedPodcast(podcast.podcast),
              episodeCount: podcast.episodeCount,
              mostRecentEpisodeDate: podcast.mostRecentEpisodeDate
            )
        } else {
          Self.log.notice("Observed podcast: \(podcast.toString) not showing in trending?")
        }
      }

      syncPodcastListToTrendingResults(trendingSection)
    }
  }

  private func restartObservation(
    feedURLs: [FeedURL],
    update: @escaping ([PodcastWithEpisodeMetadata<Podcast>]) -> Void
  ) {
    podcastObservationTask?.cancel()

    guard !feedURLs.isEmpty else {
      podcastObservationTask = nil
      return
    }

    podcastObservationTask = Task { [weak self] in
      guard let self else { return }

      do {
        for try await podcasts in observatory.podcastsWithEpisodeMetadata(feedURLs) {
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

  // MARK: - Podcast List Syncing

  private func syncPodcastListToSearchResults() {
    guard isShowingSearchResults else { return }
    podcastList.allEntries = searchResults
  }

  fileprivate func syncPodcastListToTrendingResults(_ trendingSection: TrendingSection) {
    guard !isShowingSearchResults, trendingSection == currentTrendingSection else { return }
    podcastList.allEntries = trendingSection.results
  }

  // MARK: - Disappear

  func disappear() {
    Self.log.debug("disappear: executing")

    searchText = ""
    searchTask?.cancel()
    searchTask = nil
    podcastObservationTask?.cancel()
    podcastObservationTask = nil
    for trendingSection in trendingSections {
      trendingSection.task?.cancel()
      trendingSection.task = nil
    }
  }
}
