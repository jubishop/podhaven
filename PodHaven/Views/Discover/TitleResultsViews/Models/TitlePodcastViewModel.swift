// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
class TitlePodcastViewModel:
  UnsavedEpisodeQueueableSelectableListModel,
  UnsavedPodcastQueueableModel,
  UnsavedPodcastSubscribableModel
{
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.navigation) private var navigation
  @ObservationIgnored @LazyInjected(\.observatory) private var observatory
  @ObservationIgnored @LazyInjected(\.playManager) private var playManager
  @ObservationIgnored @LazyInjected(\.queue) private var queue
  @ObservationIgnored @LazyInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  // MARK: - State Management

  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }
  var unplayedOnly: Bool = false

  var subscribable: Bool = false
  let searchText: String
  var unsavedPodcast: UnsavedPodcast
  var episodeList = SelectableListUseCase<UnsavedEpisode, GUID>(idKeyPath: \.guid)

  internal var existingPodcastSeries: PodcastSeries?
  internal var podcastFeed: PodcastFeed?

  // MARK: - Initialization

  init(titlePodcast: SearchedPodcastByTitle) {
    self.searchText = titlePodcast.searchText
    self.unsavedPodcast = titlePodcast.unsavedPodcast
    episodeList.customFilter = { [unowned self] in !self.unplayedOnly || !$0.completed }
  }

  func execute() async {
    do {
      let podcastFeed = try await PodcastFeed.parse(unsavedPodcast.feedURL)
      self.podcastFeed = podcastFeed

      for try await podcastSeries in observatory.podcastSeries(unsavedPodcast.feedURL) {
        if subscribable && existingPodcastSeries == podcastSeries { continue }
        if let podcastSeries = podcastSeries, podcastSeries.podcast.subscribed {
          navigation.showPodcast(podcastSeries)
        }

        try processPodcastSeries(podcastSeries)
      }
    } catch {
      alert.andReport(error)
    }
  }
}
