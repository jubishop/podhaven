// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
class TrendingPodcastViewModel:
  UnsavedEpisodeQueueableSelectableListModel,
  UnsavedPodcastQueueableModel,
  UnsavedPodcastSubscribableModel
{
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.navigation) private var navigation
  @ObservationIgnored @LazyInjected(\.observatory) private var observatory

  // MARK: - State Management

  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }
  var unplayedOnly: Bool = false

  var subscribable: Bool = false
  let category: String
  var unsavedPodcast: UnsavedPodcast
  var episodeList = SelectableListUseCase<UnsavedEpisode, GUID>(idKeyPath: \.guid)

  internal var existingPodcastSeries: PodcastSeries?
  internal var podcastFeed: PodcastFeed?

  // MARK: - Initialization

  init(trendingPodcast: TrendingPodcast) {
    self.category = trendingPodcast.category
    self.unsavedPodcast = trendingPodcast.unsavedPodcast
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
