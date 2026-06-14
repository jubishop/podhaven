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
  let rating: EpisodeRating?
  let tagIDs: Set<Tag.ID>
  let hasEmbedding: Bool
  let hasTranscript: Bool

  // MARK: - Podcast Fields

  let podcastImage: URL
  let podcastTitle: String
  let feedURL: FeedURL
  let defaultPlaybackRate: Double?

  // MARK: - In-Memory Fields

  var artwork: UIImage?
  var currentTime: CMTime
  var maxPlaybackTime: CMTime

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
    rating = row[Episode.Columns.rating]
    hasEmbedding = row[EpisodeEmbedding.existsColumnName]
    hasTranscript = row[Episode.hasTranscriptColumnName]

    tagIDs = try EpisodeTag.decodeTagIDs(from: row)

    let cachedFilename: String? = row[Episode.Columns.cachedFilename]
    let downloading: Bool = row[Episode.Columns.downloading]
    if cachedFilename != nil {
      cacheStatus = .cached
    } else if downloading {
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

    // artwork, currentTime, and maxPlaybackTime are managed in-memory by
    // StateManager, not read from the DB row. Reading them here would cause
    // GRDB to track the columns and re-query every 3 seconds during playback.
    artwork = nil
    currentTime = .zero
    maxPlaybackTime = .zero
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
    rating = podcastEpisode.rating
    // Tags and hasEmbedding aren't carried on PodcastEpisode; the on-deck
    // observation populates them on the next emission via the correlated
    // subqueries in `request(for:)`, so seeding empty/false here is fine.
    tagIDs = []
    hasEmbedding = false
    hasTranscript = podcastEpisode.hasTranscript
    podcastImage = podcastEpisode.podcastImage
    podcastTitle = podcastEpisode.podcastTitle
    feedURL = podcastEpisode.feedURL
    defaultPlaybackRate = podcastEpisode.podcast.defaultPlaybackRate
    artwork = nil
    currentTime = podcastEpisode.currentTime
    maxPlaybackTime = podcastEpisode.maxPlaybackTime
  }

  // MARK: - EpisodeListable

  var episodeID: Episode.ID? { id }
  var image: URL { episodeImage ?? podcastImage }
  var mediaGUID: MediaGUID { MediaGUID(guid: guid, mediaURL: mediaURL) }

  // MARK: - Column Selection

  private static var episodeColumns: [any SQLSelectable] {
    [
      Episode.Columns.id,
      Episode.Columns.guid,
      Episode.Columns.mediaURL,
      Episode.Columns.title,
      Episode.Columns.pubDate,
      Episode.Columns.duration,
      Episode.Columns.description,
      Episode.Columns.image,
      Episode.Columns.finishDate,
      Episode.Columns.queueOrder,
      Episode.Columns.saveInCache,
      Episode.Columns.rating,
      Episode.Columns.cachedFilename,
      Episode.Columns.downloading,
      EpisodeTag.tagIDsSelectable,
      EpisodeEmbedding.existsSelectable,
      Episode.hasTranscriptSelectable,
    ]
  }

  private static var podcastColumns: [any SQLSelectable] {
    [
      Podcast.Columns.image,
      Podcast.Columns.title,
      Podcast.Columns.feedURL,
      Podcast.Columns.defaultPlaybackRate,
    ]
  }

  static func request(for episodeID: Episode.ID) -> QueryInterfaceRequest<OnDeck> {
    Episode
      .withID(episodeID)
      .select(episodeColumns)
      .including(required: Episode.podcast.select(podcastColumns))
      .asRequest(of: OnDeck.self)
  }

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
      && artwork === other.artwork
  }

  // MARK: - Hashable

  // Mirrors `==`: `currentTime` is folded in so an advancing now-playing row
  // hashes differently, while `maxPlaybackTime` and `artwork` stay out.
  func hash(into hasher: inout Hasher) {
    hasher.combine(currentTime)
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
    hasher.combine(rating)
    hasher.combine(tagIDs)
    hasher.combine(hasEmbedding)
    hasher.combine(hasTranscript)
    hasher.combine(podcastImage)
    hasher.combine(podcastTitle)
    hasher.combine(feedURL)
    hasher.combine(defaultPlaybackRate)
  }

  // MARK: - Equatable

  // `currentTime` is part of equality so SwiftUI re-renders the now-playing
  // row (progress + time-remaining) as playback advances. `maxPlaybackTime`
  // and `artwork` stay out — no list row diffs on them, and the `onDeck`
  // broadcast is `.notifyAlways` so those in-memory writes still reach the
  // play bar. The on-deck observation drops `currentTime` from its tracked
  // region (see `request(for:)`), so including it here can't wake that
  // observation on per-checkpoint writes.
  //
  // Split into two short-circuited guards — a single long `&&` chain tripped
  // the Swift type-checker's complexity budget on CI cold builds. currentTime
  // leads so the common "same row, time advanced" compare fails fast.
  static func == (lhs: OnDeck, rhs: OnDeck) -> Bool {
    guard lhs.currentTime == rhs.currentTime,
      lhs.id == rhs.id,
      lhs.guid == rhs.guid,
      lhs.mediaURL == rhs.mediaURL,
      lhs.title == rhs.title,
      lhs.pubDate == rhs.pubDate,
      lhs.duration == rhs.duration,
      lhs.description == rhs.description,
      lhs.episodeImage == rhs.episodeImage,
      lhs.finishDate == rhs.finishDate,
      lhs.queueOrder == rhs.queueOrder
    else { return false }
    return lhs.cacheStatus == rhs.cacheStatus
      && lhs.saveInCache == rhs.saveInCache
      && lhs.rating == rhs.rating
      && lhs.tagIDs == rhs.tagIDs
      && lhs.hasEmbedding == rhs.hasEmbedding
      && lhs.hasTranscript == rhs.hasTranscript
      && lhs.podcastImage == rhs.podcastImage
      && lhs.podcastTitle == rhs.podcastTitle
      && lhs.feedURL == rhs.feedURL
      && lhs.defaultPlaybackRate == rhs.defaultPlaybackRate
  }
}
