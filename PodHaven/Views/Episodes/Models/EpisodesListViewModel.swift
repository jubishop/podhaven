// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
class EpisodesListViewModel:
  ManagingEpisodes,
  SelectableEpisodeList
{
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.navigation) private var navigation
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.EpisodesView.standard)

  // MARK: - State Management

  let title: String
  let filter: SQLExpression
  let order: SQLOrdering
  let limit: Int

  // MARK: - SelectableEpisodeList

  var episodeList = SelectableListUseCase<PodcastEpisode>()
  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }

  // MARK: - Initialization

  init(
    title: String,
    filter: SQLExpression = AppDB.NoOp,
    order: SQLOrdering = Episode.Columns.pubDate.desc,
    limit: Int = 100
  ) {
    self.title = title
    self.filter = filter
    self.order = order
    self.limit = limit
  }

  func execute() async {
    do {
      for try await podcastEpisodes in observatory.podcastEpisodes(
        filter: filter,
        order: order,
        limit: limit
      ) {
        try Task.checkCancellation()
        Self.log.debug("Updating \(podcastEpisodes.count) observed episodes")

        self.episodeList.allEntries = IdentifiedArray(uniqueElements: podcastEpisodes)
      }
    } catch {
      Self.log.error(error)
      guard ErrorKit.isRemarkable(error) else { return }
      alert(ErrorKit.coreMessage(for: error))
    }
  }
}
