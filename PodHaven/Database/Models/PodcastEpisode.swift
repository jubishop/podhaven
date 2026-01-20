// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import IdentifiedCollections
import Tagged
import UIKit

struct PodcastEpisode:
  Codable,
  EpisodeDisplayable,
  Equatable,
  FetchableRecord,
  Hashable
{
  var id: Episode.ID { episode.id }

  // MARK: - Data

  let podcast: Podcast
  let episode: Episode

  // MARK: - EpisodeDisplayable

  var feedURL: FeedURL { podcast.feedURL }
  var podcastTitle: String { podcast.title }
  var image: URL { episode.image ?? podcast.image }
  var podcastImage: URL { podcast.image }
  var saveInCache: Bool { episode.saveInCache }

  // MARK: - EpisodeInformable

  var mediaGUID: MediaGUID { episode.unsaved.id }
  var title: String { episode.title }
  var pubDate: Date { episode.pubDate }
  var description: String? { episode.description }
  var duration: CMTime { episode.duration }
  var currentTime: CMTime { episode.currentTime }
  var queueDate: Date? { episode.queueDate }
  var queueOrder: Int? { episode.queueOrder }
  var cacheStatus: Episode.CacheStatus { episode.cacheStatus }
  var finishDate: Date? { episode.finishDate }

  // MARK: - Reset

  func toOriginalUnsavedPodcastEpisode() throws -> UnsavedPodcastEpisode {
    UnsavedPodcastEpisode(
      unsavedPodcast: try podcast.toOriginalUnsavedPodcast(),
      unsavedEpisode: try episode.toOriginalUnsavedEpisode()
    )
  }
}
