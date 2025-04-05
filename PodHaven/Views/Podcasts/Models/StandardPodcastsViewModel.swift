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
  var podcastList = SelectableListUseCase<Podcast, FeedURL>(idKeyPath: \.feedURL)

  // MARK: - Initialization

  init(title: String, podcastFilter: SQLExpression = AppDB.NoOpFilter) {
    self.title = title
    self.podcastFilter = podcastFilter
  }

  func execute() async {
    do {
      for try await podcasts in observatory.allPodcasts(podcastFilter) {
        self.podcastList.allEntries = podcasts
      }
    } catch {
      alert.andReport(error)
    }
  }

  // MARK: - Public Functions

  func refreshPodcasts() async throws {
    try await refreshManager.performRefresh(stalenessThreshold: 1.minutesAgo, filter: podcastFilter)
  }

  func deleteSelectedPodcasts() {
    Task {
      try await repo.delete(podcastList.selectedEntries.elements.map(\.id))
    }
  }
}
