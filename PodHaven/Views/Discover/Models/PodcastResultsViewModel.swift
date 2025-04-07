// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
class PodcastResultsViewModel:
  UnsavedPodcastObservableModel,
  UnsavedPodcastQueueableModel,
  UnsavedQueueableSelectableListModel
{
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.observatory) private var observatory

  // MARK: - State Management

  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }
  var unplayedOnly: Bool = false

  var subscribable: Bool = false
  let searchedText: String
  var unsavedPodcast: UnsavedPodcast
  var episodeList = SelectableListUseCase<UnsavedEpisode, GUID>(idKeyPath: \.guid)

  internal var existingPodcastSeries: PodcastSeries?
  internal var podcastFeed: PodcastFeed?

  // MARK: - Initialization

  init(searchedPodcast: SearchedPodcast) {
    self.searchedText = searchedPodcast.searchedText
    self.unsavedPodcast = searchedPodcast.unsavedPodcast
    episodeList.customFilter = { [unowned self] in !self.unplayedOnly || !$0.completed }
  }

  func execute() async {
    do {
      let podcastFeed = try await PodcastFeed.parse(unsavedPodcast.feedURL)
      self.podcastFeed = podcastFeed

      for try await podcastSeries in observatory.podcastSeries(unsavedPodcast.feedURL) {
        if subscribable && existingPodcastSeries == podcastSeries { continue }

        try processPodcastSeries(podcastSeries)
        try processEpisodes(from: podcastFeed, merging: podcastSeries)
      }
    } catch {
      alert.andReport(error)
    }
  }

  // MARK: - EpisodeUpsertable

  func upsert(_ episode: UnsavedEpisode) async throws -> PodcastEpisode {
    let repo = Container.shared.repo()
    return try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: episode
      )
    )
  }
}
