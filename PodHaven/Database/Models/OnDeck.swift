// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation
import GRDB
import Tagged
import UIKit

struct OnDeck: EpisodeListable, FetchableRecord, Identifiable {
  // MARK: - Episode Fields

  let id: Episode.ID
  private let guid: GUID
  let mediaURL: MediaURL
  let title: String
  let pubDate: Date
  let duration: CMTime
  private let description: String?
  private let episodeImage: URL?
  let finishDate: Date?
  let queueOrder: Int?
  let cacheStatus: Episode.CacheStatus
  let saveInCache: Bool

  // MARK: - Podcast Fields

  let podcastImage: URL
  let podcastTitle: String
  let feedURL: FeedURL
  let defaultPlaybackRate: Double?

  // MARK: - In-Memory Fields

  var artwork: UIImage?
  var currentTime: CMTime

  // MARK: - FetchableRecord

  init(row: Row) throws {
    id = row[Episode.Columns.id]
    guid = row[Episode.Columns.guid]
    mediaURL = row[Episode.Columns.mediaURL]
    title = row[Episode.Columns.title]
    pubDate = row[Episode.Columns.pubDate]
    duration = row[Episode.Columns.duration]
    description = row[Episode.Columns.description]
    episodeImage = row[Episode.Columns.image]
    finishDate = row[Episode.Columns.finishDate]
    queueOrder = row[Episode.Columns.queueOrder]
    saveInCache = row[Episode.Columns.saveInCache]

    let cachedFilename: String? = row[Episode.Columns.cachedFilename]
    let downloadTaskID: URLSessionDownloadTask.ID? = row[Episode.Columns.downloadTaskID]
    if cachedFilename != nil {
      cacheStatus = .cached
    } else if downloadTaskID != nil {
      cacheStatus = .caching
    } else {
      cacheStatus = .uncached
    }

    guard let podcastRow = row.scopes["podcast"] else {
      Assert.fatal("OnDeck requires podcast scope via including(required:)")
    }
    podcastImage = podcastRow[Podcast.Columns.image]
    podcastTitle = podcastRow[Podcast.Columns.title]
    feedURL = podcastRow[Podcast.Columns.feedURL]
    defaultPlaybackRate = podcastRow[Podcast.Columns.defaultPlaybackRate]

    // artwork and currentTime are managed in-memory by StateManager, not read
    // from the DB row. Reading currentTime here would cause GRDB to track the
    // column and re-query every 3 seconds during playback.
    artwork = nil
    currentTime = .zero
  }

  // MARK: - Convenience Init

  init(from podcastEpisode: PodcastEpisode) {
    id = podcastEpisode.id
    guid = podcastEpisode.episode.unsaved.guid
    mediaURL = podcastEpisode.episode.unsaved.mediaURL
    title = podcastEpisode.title
    pubDate = podcastEpisode.pubDate
    duration = podcastEpisode.duration
    description = podcastEpisode.episode.unsaved.description
    episodeImage = podcastEpisode.episode.unsaved.image
    finishDate = podcastEpisode.finishDate
    queueOrder = podcastEpisode.queueOrder
    cacheStatus = podcastEpisode.cacheStatus
    saveInCache = podcastEpisode.saveInCache
    podcastImage = podcastEpisode.podcastImage
    podcastTitle = podcastEpisode.podcastTitle
    feedURL = podcastEpisode.feedURL
    defaultPlaybackRate = podcastEpisode.podcast.defaultPlaybackRate
    artwork = nil
    currentTime = podcastEpisode.currentTime
  }

  // MARK: - EpisodeListable

  var image: URL { episodeImage ?? podcastImage }
  var mediaGUID: MediaGUID { MediaGUID(guid: guid, mediaURL: mediaURL) }

  // MARK: - Derived Properties

  var chapters: [CMTime]? {
    Episode.chapters(from: description, duration: duration)
  }

  // MARK: - Widget Equality

  func widgetEquals(_ other: OnDeck) -> Bool {
    id == other.id
      && title == other.title
      && podcastTitle == other.podcastTitle
      && pubDate == other.pubDate
      && duration == other.duration
      && (artwork != nil) == (other.artwork != nil)
  }

  // MARK: - Hashable

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(guid)
    hasher.combine(mediaURL)
    hasher.combine(title)
    hasher.combine(pubDate)
    hasher.combine(duration)
    hasher.combine(description)
    hasher.combine(episodeImage)
    hasher.combine(finishDate)
    hasher.combine(queueOrder)
    hasher.combine(cacheStatus)
    hasher.combine(saveInCache)
    hasher.combine(podcastImage)
    hasher.combine(podcastTitle)
    hasher.combine(feedURL)
    hasher.combine(defaultPlaybackRate)
  }

  // MARK: - Equatable

  static func == (lhs: OnDeck, rhs: OnDeck) -> Bool {
    lhs.id == rhs.id
      && lhs.guid == rhs.guid
      && lhs.mediaURL == rhs.mediaURL
      && lhs.title == rhs.title
      && lhs.pubDate == rhs.pubDate
      && lhs.duration == rhs.duration
      && lhs.description == rhs.description
      && lhs.episodeImage == rhs.episodeImage
      && lhs.finishDate == rhs.finishDate
      && lhs.queueOrder == rhs.queueOrder
      && lhs.cacheStatus == rhs.cacheStatus
      && lhs.saveInCache == rhs.saveInCache
      && lhs.podcastImage == rhs.podcastImage
      && lhs.podcastTitle == rhs.podcastTitle
      && lhs.feedURL == rhs.feedURL
      && lhs.defaultPlaybackRate == rhs.defaultPlaybackRate
  }
}
