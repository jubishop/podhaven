// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation
import GRDB
import Tagged

// Lightweight episode+podcast type for list views. Reads only columns needed
// for list display from the GRDB row, so Observatory column-level tracking
// ignores changes to detail-only columns like Podcast.lastUpdate,
// Episode.link, etc. Combined with .removeDuplicates(), this prevents
// spurious list re-renders when non-visible data changes.
struct ListablePodcastEpisode: EpisodeDisplayable, FetchableRecord, Identifiable {
  // MARK: - Episode Fields

  let id: Episode.ID
  private let guid: GUID
  private let mediaURL: MediaURL
  let title: String
  let pubDate: Date
  let duration: CMTime
  let description: String?
  private let episodeImage: URL?
  let finishDate: Date?
  let currentTime: CMTime
  let queueOrder: Int?
  let queueDate: Date?
  let cacheStatus: Episode.CacheStatus
  let saveInCache: Bool

  // MARK: - Podcast Fields

  let podcastImage: URL
  let podcastTitle: String
  let feedURL: FeedURL

  // MARK: - EpisodeListable

  var image: URL { episodeImage ?? podcastImage }
  var mediaGUID: MediaGUID { MediaGUID(guid: guid, mediaURL: mediaURL) }

  // MARK: - Searchable

  var searchableString: String { "\(title) - \(podcastTitle) - \(description ?? "")" }

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
    currentTime = row[Episode.Columns.currentTime]
    queueOrder = row[Episode.Columns.queueOrder]
    queueDate = row[Episode.Columns.queueDate]
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
      Assert.fatal("ListablePodcastEpisode requires podcast scope via including(required:)")
    }
    podcastImage = podcastRow[Podcast.Columns.image]
    podcastTitle = podcastRow[Podcast.Columns.title]
    feedURL = podcastRow[Podcast.Columns.feedURL]
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
    hasher.combine(currentTime)
    hasher.combine(queueOrder)
    hasher.combine(queueDate)
    hasher.combine(cacheStatus)
    hasher.combine(saveInCache)
    hasher.combine(podcastImage)
    hasher.combine(podcastTitle)
    hasher.combine(feedURL)
  }

  // MARK: - Equatable

  static func == (lhs: ListablePodcastEpisode, rhs: ListablePodcastEpisode) -> Bool {
    lhs.id == rhs.id
      && lhs.guid == rhs.guid
      && lhs.mediaURL == rhs.mediaURL
      && lhs.title == rhs.title
      && lhs.pubDate == rhs.pubDate
      && lhs.duration == rhs.duration
      && lhs.description == rhs.description
      && lhs.episodeImage == rhs.episodeImage
      && lhs.finishDate == rhs.finishDate
      && lhs.currentTime == rhs.currentTime
      && lhs.queueOrder == rhs.queueOrder
      && lhs.queueDate == rhs.queueDate
      && lhs.cacheStatus == rhs.cacheStatus
      && lhs.saveInCache == rhs.saveInCache
      && lhs.podcastImage == rhs.podcastImage
      && lhs.podcastTitle == rhs.podcastTitle
      && lhs.feedURL == rhs.feedURL
  }
}
