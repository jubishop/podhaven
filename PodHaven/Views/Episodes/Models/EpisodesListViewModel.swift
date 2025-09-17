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

  var episodeList = SelectableListUseCase<PodcastEpisode, Episode.ID>(idKeyPath: \.id)
  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }

  // MARK: - ManagingEpisodes

  func getOrCreatePodcastEpisode(_ episode: any EpisodeDisplayable) async throws -> PodcastEpisode {
    try await DisplayableEpisode.getOrCreatePodcastEpisode(episode)
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
        Self.log.debug(
          """
          Updating observed episodes:
            \(podcastEpisodes.map(\.toString).joined(separator: "\n  "))
          """
        )
        self.episodeList.allEntries = IdentifiedArray(uniqueElements: podcastEpisodes)
      }
    } catch {
      Self.log.error(error)
      if !ErrorKit.isRemarkable(error) { return }
      await alert(ErrorKit.coreMessage(for: error))
    }
  }

  // MARK: - Navigation Actions

  func showPodcast(for episode: PodcastEpisode) {
    Self.log.debug("Showing podcast for episode: \(episode.toString)")
    navigation.showPodcast(episode.podcast)
  }
}
