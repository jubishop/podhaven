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

@Observable @MainActor
final class SearchViewModel {
  @ObservationIgnored @DynamicInjected(\.searchService) private var searchService
  @ObservationIgnored @DynamicInjected(\.sleeper) private var sleeper

  private static let log = Log.as(LogSubsystem.SearchView.main)

  // MARK: - Configuration

  private static let debounceDuration: Duration = .milliseconds(350)

  // MARK: - Internal State

  enum LoadingState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
  }

  // MARK: - Trending State

  var trendingState: LoadingState = .idle

  typealias TrendingSectionID = Tagged<SearchViewModel, String>
  struct TrendingSection: Identifiable, Equatable {
    let genreID: Int?
    let icon: AppIcon
    fileprivate var state: LoadingState
    fileprivate var cachedPodcasts: [UnsavedPodcast]

    fileprivate init(
      genreID: Int?,
      icon: AppIcon,
      state: LoadingState = .idle,
      podcasts: [UnsavedPodcast] = []
    ) {
      self.genreID = genreID
      self.icon = icon
      self.state = state
      self.cachedPodcasts = podcasts
    }

    var id: TrendingSectionID { TrendingSectionID(icon.text) }
    var title: String { icon.text }
    var podcasts: [UnsavedPodcast] { cachedPodcasts }
  }

  let defaultTrendingSection = TrendingSection(genreID: nil, icon: .trendingTop)
  var trendingSections: IdentifiedArrayOf<TrendingSection>
  var currentTrendingSectionID: TrendingSectionID = TrendingSectionID(AppIcon.trendingTop.text)
  var currentTrendingSection: TrendingSection {
    trendingSections[id: currentTrendingSectionID] ?? defaultTrendingSection
  }

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

  @ObservationIgnored private var searchTask: Task<Void, Never>?
  @ObservationIgnored private var trendingSectionTasks: [TrendingSectionID: Task<Void, Never>] = [:]

  // MARK: - Initialization

  init() {
    trendingSections = IdentifiedArray(
      uniqueElements: [
        defaultTrendingSection,
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
    loadTrendingSectionIfNeeded(id: currentTrendingSectionID)
  }

  // MARK: - Trending

  func selectTrendingSection(_ trendingSectionID: TrendingSectionID) {
    guard trendingSections[id: trendingSectionID] != nil else { return }
    currentTrendingSectionID = trendingSectionID
    loadTrendingSectionIfNeeded(id: trendingSectionID)
  }

  func refreshCurrentTrendingSection() async {
    trendingSectionTasks[currentTrendingSectionID]?.cancel()
    trendingSectionTasks[currentTrendingSectionID] = nil

    updateTrendingSection(with: currentTrendingSectionID) { mutableSection in
      mutableSection.cachedPodcasts = []
      mutableSection.state = .idle
    }

    if case .error = trendingState {
      trendingState = .idle
    }

    let task = startTrendingFetch(
      for: currentTrendingSectionID,
      genreID: currentTrendingSection.genreID
    )
    await task.value
  }

  private func loadTrendingSectionIfNeeded(id: TrendingSectionID) {
    guard let section = trendingSections[id: id] else { return }

    switch section.state {
    case .loaded:
      if currentTrendingSectionID == id {
        trendingState = .loaded
      }
      return
    case .loading:
      if currentTrendingSectionID == id {
        trendingState = .loading
      }
      return
    default:
      break
    }

    startTrendingFetch(for: id, genreID: section.genreID)
  }

  private func completeTrendingSectionLoad(
    id: TrendingSectionID,
    podcasts: [UnsavedPodcast],
    errorMessage: String?
  ) {
    updateTrendingSection(with: id) { mutableSection in
      if let errorMessage {
        mutableSection.cachedPodcasts = []
        mutableSection.state = .error(errorMessage)
      } else {
        mutableSection.cachedPodcasts = podcasts
        mutableSection.state = .loaded
      }
    }

    trendingSectionTasks[id] = nil

    guard currentTrendingSectionID == id else { return }

    if let errorMessage {
      trendingState = .error(errorMessage)
    } else {
      trendingState = .loaded
    }
  }

  private func updateTrendingSection(
    with id: TrendingSectionID,
    transform: (inout TrendingSection) -> Void
  ) {
    guard var section = trendingSections[id: id] else { return }
    transform(&section)
    trendingSections[id: id] = section
  }

  @discardableResult
  private func startTrendingFetch(
    for id: TrendingSectionID,
    genreID: Int?
  ) -> Task<Void, Never> {
    updateTrendingSection(with: id) { mutableSection in
      mutableSection.state = .loading
    }

    if currentTrendingSectionID == id {
      trendingState = .loading
    }

    let task = Task { @MainActor [weak self] in
      guard let self else { return }

      do {
        let results = try await self.searchService.topPodcasts(
          genreID: genreID,
          limit: 48
        )
        try Task.checkCancellation()

        let podcasts = Array(results)
        if podcasts.isEmpty {
          self.completeTrendingSectionLoad(
            id: id,
            podcasts: [],
            errorMessage: "No podcasts available in this category right now."
          )
        } else {
          self.completeTrendingSectionLoad(id: id, podcasts: podcasts, errorMessage: nil)
        }
      } catch {
        guard !Task.isCancelled else { return }
        Self.log.error(error)
        self.completeTrendingSectionLoad(
          id: id,
          podcasts: [],
          errorMessage: ErrorKit.message(for: error)
        )
      }
    }

    trendingSectionTasks[id] = task
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
    trendingSectionTasks.values.forEach { $0.cancel() }
    trendingSectionTasks.removeAll()
  }
}
