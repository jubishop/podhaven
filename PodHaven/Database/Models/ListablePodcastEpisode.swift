// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Tagged

// Lightweight episode+podcast type for list views. Reads only columns needed
// for list display from the GRDB row, so Observatory column-level tracking
// ignores changes to detail-only columns like Podcast.lastUpdate,
// Episode.link, etc. Combined with .removeDuplicates(), this prevents
// spurious list re-renders when non-visible data changes.
struct ListablePodcastEpisode: EpisodeListable, Searchable, FetchableRecord, Identifiable {
  @DynamicInjected(\.repo) private var repo

  // MARK: - Episode Fields

  let id: Episode.ID
  private let guid: GUID
  private let mediaURL: MediaURL
  let title: String
  let pubDate: Date
  let duration: CMTime
  private let episodeImage: URL?
  let finishDate: Date?
  let currentTime: CMTime
  let queueOrder: Int?
  let cacheStatus: Episode.CacheStatus
  let saveInCache: Bool

  // MARK: - Podcast Fields

  let feedURL: FeedURL
  let podcastImage: URL
  let podcastTitle: String

  // MARK: - EpisodeListable

  var image: URL { episodeImage ?? podcastImage }
  var mediaGUID: MediaGUID { MediaGUID(guid: guid, mediaURL: mediaURL) }

  // MARK: - Searchable

  var searchableString: String { "\(title) - \(podcastTitle)" }

  // MARK: - FetchableRecord

  init(row: Row) throws {
    id = row[Episode.Columns.id]
    guid = row[Episode.Columns.guid]
    mediaURL = row[Episode.Columns.mediaURL]
    title = row[Episode.Columns.title]
    pubDate = row[Episode.Columns.pubDate]
    duration = row[Episode.Columns.duration]
    episodeImage = row[Episode.Columns.image]
    finishDate = row[Episode.Columns.finishDate]
    currentTime = row[Episode.Columns.currentTime]
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
      Assert.fatal("ListablePodcastEpisode requires podcast scope via including(required:)")
    }
    feedURL = podcastRow[Podcast.Columns.feedURL]
    podcastImage = podcastRow[Podcast.Columns.image]
    podcastTitle = podcastRow[Podcast.Columns.title]
  }

  // MARK: - Hashable

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(guid)
    hasher.combine(mediaURL)
    hasher.combine(title)
    hasher.combine(pubDate)
    hasher.combine(duration)
    hasher.combine(episodeImage)
    hasher.combine(finishDate)
    hasher.combine(currentTime)
    hasher.combine(queueOrder)
    hasher.combine(cacheStatus)
    hasher.combine(saveInCache)
    hasher.combine(feedURL)
    hasher.combine(podcastImage)
    hasher.combine(podcastTitle)
  }

  // MARK: - Equatable

  static func == (lhs: ListablePodcastEpisode, rhs: ListablePodcastEpisode) -> Bool {
    lhs.id == rhs.id
      && lhs.guid == rhs.guid
      && lhs.mediaURL == rhs.mediaURL
      && lhs.title == rhs.title
      && lhs.pubDate == rhs.pubDate
      && lhs.duration == rhs.duration
      && lhs.episodeImage == rhs.episodeImage
      && lhs.finishDate == rhs.finishDate
      && lhs.currentTime == rhs.currentTime
      && lhs.queueOrder == rhs.queueOrder
      && lhs.cacheStatus == rhs.cacheStatus
      && lhs.saveInCache == rhs.saveInCache
      && lhs.feedURL == rhs.feedURL
      && lhs.podcastImage == rhs.podcastImage
      && lhs.podcastTitle == rhs.podcastTitle
  }

  func getPodcastEpisode() async throws -> PodcastEpisode {
    guard let podcastEpisode = try await repo.podcastEpisode(id) else {
      Assert.fatal("PodcastEpisode not found for ID \(id)")
    }
    return podcastEpisode
  }
}
