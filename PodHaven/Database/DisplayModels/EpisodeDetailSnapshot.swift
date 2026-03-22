// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation

struct EpisodeDetailSnapshot: EpisodeDisplayable, Hashable, Sendable {
  let episodeID: Episode.ID?
  let mediaGUID: MediaGUID
  let feedURL: FeedURL
  let title: String
  let podcastTitle: String
  let pubDate: Date
  let description: String?
  let duration: CMTime
  let currentTime: CMTime
  let queueDate: Date?
  let queueOrder: Int?
  let cacheStatus: Episode.CacheStatus
  let finishDate: Date?
  let image: URL
  let podcastImage: URL
  let saveInCache: Bool

  var id: MediaGUID { mediaGUID }

  init(_ listedEpisode: ListedEpisode) {
    if let unsavedPodcastEpisode = listedEpisode.getUnsavedPodcastEpisode() {
      episodeID = unsavedPodcastEpisode.episodeID
      mediaGUID = unsavedPodcastEpisode.mediaGUID
      feedURL = unsavedPodcastEpisode.feedURL
      title = unsavedPodcastEpisode.title
      podcastTitle = unsavedPodcastEpisode.podcastTitle
      pubDate = unsavedPodcastEpisode.pubDate
      description = unsavedPodcastEpisode.description
      duration = unsavedPodcastEpisode.duration
      currentTime = unsavedPodcastEpisode.currentTime
      queueDate = unsavedPodcastEpisode.queueDate
      queueOrder = unsavedPodcastEpisode.queueOrder
      cacheStatus = unsavedPodcastEpisode.cacheStatus
      finishDate = unsavedPodcastEpisode.finishDate
      image = unsavedPodcastEpisode.image
      podcastImage = unsavedPodcastEpisode.podcastImage
      saveInCache = unsavedPodcastEpisode.saveInCache
    } else if let listablePodcastEpisode = listedEpisode.getListablePodcastEpisode() {
      episodeID = listablePodcastEpisode.id
      mediaGUID = listablePodcastEpisode.mediaGUID
      feedURL = listablePodcastEpisode.feedURL
      title = listablePodcastEpisode.title
      podcastTitle = listablePodcastEpisode.podcastTitle
      pubDate = listablePodcastEpisode.pubDate
      description = nil
      duration = listablePodcastEpisode.duration
      currentTime = listablePodcastEpisode.currentTime
      queueDate = nil
      queueOrder = listablePodcastEpisode.queueOrder
      cacheStatus = listablePodcastEpisode.cacheStatus
      finishDate = listablePodcastEpisode.finishDate
      image = listablePodcastEpisode.image
      podcastImage = listablePodcastEpisode.podcastImage
      saveInCache = listablePodcastEpisode.saveInCache
    } else {
      Assert.fatal("Cannot build EpisodeDetailSnapshot from: \(type(of: listedEpisode.episode))")
    }
  }
}
