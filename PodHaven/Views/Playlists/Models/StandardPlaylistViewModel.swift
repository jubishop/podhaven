// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
class StandardPlaylistViewModel:
  PodcastQueueableModel,
  QueueableSelectableEpisodeList
{
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  var playManager: PlayManager { get async { await Container.shared.playManager() } }

  // MARK: - State Management

  var episodeList = SelectableListUseCase<PodcastEpisode, Episode.ID>(idKeyPath: \.id)
  let title: String
  let filter: SQLExpression
  let order: SQLOrdering

  // MARK: - Initialization

  init(
    title: String,
    filter: SQLExpression = AppDB.NoOp,
    order: SQLOrdering = Episode.Columns.pubDate.desc
  ) {
    self.title = title
    self.filter = filter
    self.order = order
  }

  func execute() async {
    do {
      for try await podcastEpisodes in observatory.podcastEpisodes(filter: filter, order: order) {
        self.episodeList.allEntries = IdentifiedArray(uniqueElements: podcastEpisodes)
      }
    } catch {
      alert("Couldn't execute CompletedViewModel")
    }
  }
}
