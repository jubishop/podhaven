// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import Sharing
import SwiftUI
import Tagged
import UIKit

@Observable @MainActor
class SearchViewModel:
  DisplayingPodcasts,
  ManagingPodcasts,
  SelectablePodcastList,
  SortablePodcastList
{
  @ObservationIgnored @DynamicInjected(\.iTunesService) private var iTunesService
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.notifications) private var notifications

  private static let log = Log.as(LogSubsystem.SearchView.main)

  // MARK: - ManagingPodcasts

  func getOrCreatePodcast(_ displayedPodcast: DisplayedPodcast) async throws -> Podcast {
    try await displayedPodcast.getOrCreatePodcast()
  }

  // MARK: - SelectablePodcastList & SortablePodcastList

  var podcastList = PowerList<PodcastWithEpisodeMetadata<DisplayedPodcast>>()

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

  enum SortMethod: SortingMethod {
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
        return .sortByNewest
      case .byEpisodeCount:
        return .sortByEpisodeCount
      }
    }

    var sortMethod:
      (
        @Sendable (
          PodcastWithEpisodeMetadata<DisplayedPodcast>,
          PodcastWithEpisodeMetadata<DisplayedPodcast>
        ) -> Bool
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

    var filterMethod: (@Sendable (PodcastWithEpisodeMetadata<DisplayedPodcast>) -> Bool)? {
      switch self {
      case .byMostRecentEpisode:
        return { $0.mostRecentEpisodeDate != nil }
      default: return nil
      }
    }
  }

  let allSortMethods = SortMethod.allCases
  var currentSortMethod: SortMethod = .byServerOrder {
    didSet {
      podcastList.filterMethod = currentSortMethod.filterMethod
      podcastList.sortMethod = currentSortMethod.sortMethod
    }
  }

  // MARK: - State Management

  @ObservationIgnored @Shared(.appStorage("SearchView-displayMode"))
  var displayMode: PodcastDisplayMode = .grid

  enum LoadingState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
  }

  // MARK: - Trending State

  @Observable @MainActor class TrendingSection: Hashable, @MainActor Identifiable {
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
    static func == (lhs: TrendingSection, rhs: TrendingSection) -> Bool {
      lhs.genreID == rhs.genreID && lhs.icon == rhs.icon
    }
    func hash(into hasher: inout Hasher) {
      hasher.combine(genreID)
      hasher.combine(icon)
    }
  }
  let trendingSections: [TrendingSection]

  private(set) var currentTrendingSection: TrendingSection

  // MARK: - Search State

  var searchText: String {
    get { searchDebouncer.currentValue }
    set { searchDebouncer.currentValue = newValue }
  }
  @ObservationIgnored private lazy var searchDebouncer = Debouncer(
    initialValue: "",
    debounceDuration: .milliseconds(400)
  ) { [weak self] _ in
    guard let self else { return }

    if searchedText.isEmpty {
      searchResults = []
      showTrendingSection(currentTrendingSection)
    } else if await executeSearch() {
      restartObservationForSearchResults()
    }
  }

  var searchedText: String {
    searchDebouncer.debouncedValue.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var searchState: LoadingState = .idle
  var searchResults: IdentifiedArrayOf<PodcastWithEpisodeMetadata<DisplayedPodcast>> = [] {
    didSet {
      syncPodcastListToSearchResults()
    }
  }
  var isShowingSearchResults: Bool { !searchedText.isEmpty }

  @ObservationIgnored private var currentResultsObservationTask: Task<Void, Never>?
  @ObservationIgnored private var searchTask: Task<Bool, Never>?

  // MARK: - Initialization

  init() {
    let topTrendingSection = TrendingSection(genreID: nil, icon: .trendingTop)
    currentTrendingSection = topTrendingSection
    trendingSections = [
      topTrendingSection,
      TrendingSection(genreID: 1301, icon: .trendingArts),
      TrendingSection(genreID: 1321, icon: .trendingBusiness),
      TrendingSection(genreID: 1303, icon: .trendingComedy),
      TrendingSection(genreID: 1304, icon: .trendingEducation),
      TrendingSection(genreID: 1511, icon: .trendingGovernment),
      TrendingSection(genreID: 1512, icon: .trendingHealth),
      TrendingSection(genreID: 1462, icon: .trendingHistory),
      TrendingSection(genreID: 1305, icon: .trendingKids),
      TrendingSection(genreID: 1323, icon: .trendingLeisure),
      TrendingSection(genreID: 1310, icon: .trendingMusic),
      TrendingSection(genreID: 1489, icon: .trendingNews),
      TrendingSection(genreID: 1533, icon: .trendingScience),
      TrendingSection(genreID: 1324, icon: .trendingSocietyCulture),
      TrendingSection(genreID: 1545, icon: .trendingSports),
      TrendingSection(genreID: 1318, icon: .trendingTechnology),
      TrendingSection(genreID: 1488, icon: .trendingTrueCrime),
      TrendingSection(genreID: 1309, icon: .trendingTVFilm),
    ]

    podcastList.sortMethod = currentSortMethod.sortMethod
  }

  func appear() {
    Self.log.debug("SearchViewModel: appearing")

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
      let results = try await iTunesService.topPodcasts(genreID: trendingSection.genreID, limit: 72)
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
        Self.log.debug(
          """
          Set trending results for trending section: \(trendingSection)
            With \(trendingSection.results.count) trending results.
          """
        )
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
    if await executeSearch() {
      restartObservationForSearchResults()
    }
  }

  private func executeSearch() async -> Bool {
    guard searchedText != "" else { return false }

    searchTask?.cancel()
    searchState = .loading

    let task = Task<Bool, Never> { [weak self] in
      guard let self else { return false }

      do {
        let term = searchedText
        let results = try await self.iTunesService.searchedPodcasts(matching: term, limit: 48)
        try Task.checkCancellation()
        guard term == searchedText else { return false }

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
        Self.log.debug(
          """
          Set search results for search term: \(term)
            With \(results.count) search results.
          """
        )
      } catch {
        Self.log.error(error, mundane: .trace)
        guard !Task.isCancelled else { return false }

        searchResults = []
        searchState = .error(ErrorKit.coreMessage(for: error))
      }
      return true
    }

    searchTask = task
    return await task.value
  }

  // MARK: - Observation

  private func restartObservationForSearchResults() {
    guard isShowingSearchResults else { return }

    restartObservation(feedURLs: Array(searchResults.ids)) { [weak self] podcasts in
      guard let self else { return }

      Self.log.debug(
        """
        Observed:
          search term: \(searchedText)
          \(podcasts.count) saved podcasts
        """
      )
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

    restartObservation(feedURLs: Array(trendingSection.results.ids)) {
      [weak self, trendingSection] podcasts in
      guard let self else { return }

      Self.log.debug(
        """
        Observed:
          trendingSection: \(trendingSection)
          \(podcasts.count) saved podcasts
        """
      )
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
    currentResultsObservationTask?.cancel()

    guard !feedURLs.isEmpty else {
      currentResultsObservationTask = nil
      return
    }

    currentResultsObservationTask = Task { [weak self] in
      guard let self else { return }

      do {
        for try await podcasts in observatory.podcastsWithEpisodeMetadata(feedURLs) {
          try Task.checkCancellation()
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
    Self.log.debug("SearchViewModel: disappearing")

    searchDebouncer.reset()
    searchTask?.cancel()
    searchTask = nil
    for trendingSection in trendingSections {
      trendingSection.task?.cancel()
      trendingSection.task = nil
    }
    currentResultsObservationTask?.cancel()
    currentResultsObservationTask = nil
  }
}
