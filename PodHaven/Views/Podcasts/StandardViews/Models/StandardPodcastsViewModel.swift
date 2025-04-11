// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor final class StandardPodcastsViewModel {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.observatory) private var observatory
  @ObservationIgnored @LazyInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  // MARK: - State Management

  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }

  let title: String
  let podcastFilter: SQLExpression

  var podcastList = SelectableListUseCase<PodcastWithLatestEpisodeDates, Podcast.ID>(
    idKeyPath: \.id
  )
  var anySelectedSubscribed: Bool {
    podcastList.selectedEntries.contains { $0.subscribed == true }
  }
  var anySelectedUnsubscribed: Bool {
    podcastList.selectedEntries.contains { $0.subscribed == false }
  }

  enum SortMethod {
    case byTitle
    case byMostRecentUnplayed
  }
  //  private let sortMethods: Dictionary<SortMethod, (Podcast, Podcast) -> Bool> = [
  //    .byTitle: { $0.title < $1.title },
  //    .byMostRecentUnplayed: {
  ////      $0.mostRecentUnplayedEpisodeDate ?? Date.distantPast
  ////      < $1.mostRecentUnplayedEpisodeDate ?? Date.distantPast
  //      true
  //    },
  //  ]
  var currentSortMethod = SortMethod.byTitle

  // MARK: - Initialization

  init(title: String, podcastFilter: SQLExpression = AppDB.NoOpFilter) {
    self.title = title
    self.podcastFilter = podcastFilter
  }

  func execute() async {
    do {
      print("awaiting podcasts")
      for try await podcastsWithLatestEpisodeDates in observatory.allPodcastsWithLatestEpisodeDates(
        podcastFilter
      ) {
        print("got episodes")
        print(podcastsWithLatestEpisodeDates)
        self.podcastList.allEntries = IdentifiedArray(
          uniqueElements: podcastsWithLatestEpisodeDates
        )
      }
    } catch {
      print("caught error")
      alert.andReport(error)
    }
  }

  // MARK: - Public Functions

  func refreshPodcasts() async throws {
    try await refreshManager.performRefresh(stalenessThreshold: 1.minutesAgo, filter: podcastFilter)
  }

  func deleteSelectedPodcasts() {
    Task {
      try await repo.delete(podcastList.selectedEntryIDs)
    }
  }

  func subscribeSelectedPodcasts() {
    Task {
      try await repo.markSubscribed(podcastList.selectedEntryIDs)
    }
  }

  func unsubscribeSelectedPodcasts() {
    Task {
      try await repo.markUnsubscribed(podcastList.selectedEntryIDs)
    }
  }
}
