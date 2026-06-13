// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation

struct EpisodeDetailContent:
  EpisodeDisplayable,
  Hashable,
  Sendable
{
  let episodeID: Episode.ID?
  let mediaGUID: MediaGUID
  let feedURL: FeedURL
  let title: String
  let pubDate: Date
  let duration: CMTime
  let currentTime: CMTime
  let queueOrder: Int?
  let cacheStatus: Episode.CacheStatus
  let saveInCache: Bool
  let finishDate: Date?
  let rating: EpisodeRating?
  let hasTranscript: Bool
  let decodedTranscript: Transcript?
  let image: URL
  let podcastImage: URL
  let podcastTitle: String
  let description: String?
  let queueDate: Date?
  let loaded: DisplayedEpisode?

  var id: MediaGUID { mediaGUID }

  init(initial listed: ListedEpisode) {
    episodeID = listed.episodeID
    mediaGUID = listed.mediaGUID
    feedURL = listed.feedURL
    title = listed.title
    pubDate = listed.pubDate
    duration = listed.duration
    currentTime = listed.currentTime
    queueOrder = listed.queueOrder
    cacheStatus = listed.cacheStatus
    saveInCache = listed.saveInCache
    finishDate = listed.finishDate
    rating = listed.rating
    hasTranscript = false
    decodedTranscript = nil
    image = listed.image
    podcastImage = listed.podcastImage
    podcastTitle = listed.podcastTitle
    description = listed.description
    queueDate = listed.queueDate
    loaded = nil
  }

  init(loaded displayed: DisplayedEpisode) {
    episodeID = displayed.episodeID
    mediaGUID = displayed.mediaGUID
    feedURL = displayed.feedURL
    title = displayed.title
    pubDate = displayed.pubDate
    duration = displayed.duration
    currentTime = displayed.currentTime
    queueOrder = displayed.queueOrder
    cacheStatus = displayed.cacheStatus
    saveInCache = displayed.saveInCache
    finishDate = displayed.finishDate
    rating = displayed.rating
    hasTranscript = displayed.hasTranscript
    decodedTranscript = displayed.decodedTranscript
    image = displayed.image
    podcastImage = displayed.podcastImage
    podcastTitle = displayed.podcastTitle
    description = displayed.description
    queueDate = displayed.queueDate
    loaded = displayed
  }
}
