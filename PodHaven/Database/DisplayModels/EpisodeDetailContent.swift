// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation

// Flat, view-facing snapshot of `EpisodeDetailViewModel.state`. Built via
// `init(initial:)` from the transient list-row before the saved episode
// hydrates, or `init(loaded:)` from the fully-displayable episode (saved or
// unsaved). `loaded` is non-nil only in the latter case — source flavor and
// other `DisplayedEpisode`-only data are reachable through it. SwiftUI diffs
// by visible content rather than by source identity, so two states that
// project to the same fields hash equal.
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
    image = displayed.image
    podcastImage = displayed.podcastImage
    podcastTitle = displayed.podcastTitle
    description = displayed.description
    queueDate = displayed.queueDate
    loaded = displayed
  }
}
