// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import SavedMacro
import Tagged

// MARK: - EpisodeRating

enum EpisodeRating: String, CaseIterable, Codable, DatabaseValueConvertible, Hashable, Sendable {
  case loved
  case liked
  case disliked
  case notInterested
}

typealias GUID = Tagged<UnsavedEpisode, String>
enum MediaURLTag {}
typealias MediaURL = Tagged<MediaURLTag, URL>
enum CachedURLTag {}
typealias CachedURL = Tagged<CachedURLTag, URL>
struct MediaGUID: Codable, CustomStringConvertible, Equatable, Hashable {
  let guid: GUID
  let mediaURL: MediaURL

  var description: String {
    "GUID: \(guid.toString), MediaURL: \(mediaURL.toString)"
  }
}

struct UnsavedEpisode:
  EpisodeFoundational,
  Identifiable,
  RSSUpdatable,
  Savable,
  Searchable
{
  var id: MediaGUID { MediaGUID(guid: guid, mediaURL: mediaURL) }
  var episodeID: Episode.ID? { nil }

  private static let log = Log.as(LogSubsystem.Database.episode)

  static let databaseTableName: String = "episode"

  var podcastId: Podcast.ID?

  // Feed
  let guid: GUID
  let mediaURL: MediaURL
  let title: String
  let pubDate: Date
  let duration: CMTime
  let description: String?
  let link: URL?
  let image: URL?

  // User
  let finishDate: Date?
  let currentTime: CMTime
  let maxPlaybackTime: CMTime
  // Boundary-flipped mirror of `currentTime > 0`; observation filters read it
  // so per-checkpoint playback writes stay out of their tracked regions.
  let playbackStarted: Bool
  let queueOrder: Int?
  let queueDate: Date?
  private let cachedFilename: String?
  let downloading: Bool
  let saveInCache: Bool
  let rating: EpisodeRating?
  let ratingDate: Date?
  private let transcript: String?

  init(
    podcastId: Podcast.ID? = nil,
    guid: GUID,
    mediaURL: MediaURL,
    title: String,
    pubDate: Date?,
    duration: CMTime?,
    description: String?,
    link: URL?,
    image: URL?,
    finishDate: Date? = nil,
    currentTime: CMTime? = nil,
    maxPlaybackTime: CMTime? = nil,
    queueOrder: Int? = nil,
    queueDate: Date? = nil,
    cachedFilename: String? = nil,
    downloading: Bool = false,
    saveInCache: Bool = false,
    rating: EpisodeRating? = nil,
    ratingDate: Date? = nil,
    transcript: String? = nil
  ) throws {
    self.podcastId = podcastId
    self.guid = guid
    self.mediaURL = try mediaURL.convertToHTTPSURL()
    self.title = title
    self.pubDate = pubDate ?? Date()
    self.duration = duration ?? CMTime.zero
    self.description = description
    if let link {
      do {
        self.link = try link.convertToHTTPSURL()
      } catch {
        Self.log.caughtError(
          "Invalid link URL '\(link)' for episode '\(title)'",
          error,
          level: .info
        )
        self.link = nil
      }
    } else {
      self.link = nil
    }
    if let image {
      do {
        self.image = try image.convertToHTTPSURL()
      } catch {
        Self.log.caughtError(
          "Invalid image URL '\(image)' for episode '\(title)'",
          error,
          level: .info
        )
        self.image = nil
      }
    } else {
      self.image = nil
    }
    self.finishDate = finishDate
    self.currentTime = currentTime ?? CMTime.zero
    self.maxPlaybackTime = maxPlaybackTime ?? CMTime.zero
    self.playbackStarted = self.currentTime.seconds > 0
    self.queueOrder = queueOrder
    self.queueDate = queueDate
    self.cachedFilename = cachedFilename
    self.downloading = downloading
    self.saveInCache = saveInCache
    self.rating = rating
    self.ratingDate = ratingDate
    self.transcript = transcript
  }

  // MARK: - EpisodeFoundational

  var mediaGUID: MediaGUID { MediaGUID(guid: guid, mediaURL: mediaURL) }
  var cacheStatus: Episode.CacheStatus {
    .from(cachedFilename: cachedFilename, downloading: downloading)
  }

  // MARK: - Searchable

  var searchableString: String { "\(title) - \(description ?? "")" }

  // MARK: - Chapters

  var chapters: [CMTime]? {
    Episode.chapters(from: description, duration: duration)
  }

  // MARK: - Cached Info

  var cachedURL: CachedURL? {
    guard let cachedFilename = cachedFilename
    else { return nil }

    return CacheManager.resolveCachedFilepath(for: cachedFilename)
  }

  // MARK: - Transcript

  var hasTranscript: Bool { transcript != nil }

  var decodedTranscript: Transcript? {
    guard let transcript else { return nil }

    do {
      return try Transcript(decoding: transcript)
    } catch {
      Self.log.caughtError("Failed to decode transcript for '\(title)'", error)
      return nil
    }
  }

  // MARK: - RSSUpdatable

  var rssUpdatableColumns: [(any ColumnExpression, any SQLExpressible)] {
    [
      (Episode.Columns.guid, guid),
      (Episode.Columns.mediaURL, mediaURL),
      (Episode.Columns.title, title),
      (Episode.Columns.pubDate, pubDate),
      (Episode.Columns.description, description),
      (Episode.Columns.link, link),
      (Episode.Columns.image, image),
    ]
  }

  func rssEquals(_ other: UnsavedEpisode) -> Bool {
    guid == other.guid
      && mediaURL == other.mediaURL
      && title == other.title
      && pubDate == other.pubDate
      && description == other.description
      && link == other.link
      && image == other.image
  }

  // MARK: - Reset

  func toOriginalUnsavedEpisode() throws -> UnsavedEpisode {
    try UnsavedEpisode(
      podcastId: podcastId,
      guid: guid,
      mediaURL: mediaURL,
      title: title,
      pubDate: pubDate,
      duration: duration,
      description: description,
      link: link,
      image: image
    )
  }
}

@Saved<UnsavedEpisode>
struct Episode: EpisodeFoundational, Saved, RSSUpdatable, Searchable {
  // MARK: - EpisodeFoundational

  var episodeID: Episode.ID? { id }

  // MARK: - Stringable / Searchable

  var toString: String { "[\(id)] - \(unsaved.toString)" }
  var searchableString: String { unsaved.searchableString }

  // MARK: - Associations

  static let embedding = hasOne(EpisodeEmbedding.self)
  static let episodeTags = hasMany(EpisodeTag.self)
  static let podcast = belongsTo(Podcast.self)
  static let tags = hasMany(Tag.self, through: episodeTags, using: EpisodeTag.tag).order(\.name)
  var podcastID: Podcast.ID {
    guard let podcastID = self.podcastId else {
      Assert.fatal("Episode \(id) is missing required podcastId")
    }

    return podcastID
  }

  // MARK: - SQL Expressions

  static let queued: SQLExpression = Columns.queueOrder != nil
  static let unqueued: SQLExpression = Columns.queueOrder == nil
  static let cached: SQLExpression = Columns.cachedFilename != nil
  static let savedInCache: SQLExpression = cached && Columns.saveInCache == true
  static let finished: SQLExpression = Columns.finishDate != nil
  static let unfinished: SQLExpression = Columns.finishDate == nil
  // Read the boundary-flipped flag, not currentTime: observations filtering
  // on these must not wake on per-checkpoint playback writes.
  static let unstarted: SQLExpression = Columns.playbackStarted == false
  static let started: SQLExpression = Columns.playbackStarted == true
  static let previouslyQueued: SQLExpression = Columns.queueDate != nil
  static let loved: SQLExpression = Columns.rating == EpisodeRating.loved.rawValue
  static let liked: SQLExpression = Columns.rating == EpisodeRating.liked.rawValue
  static let disliked: SQLExpression = Columns.rating == EpisodeRating.disliked.rawValue
  static let notInterested: SQLExpression =
    Columns.rating == EpisodeRating.notInterested.rawValue
  static let rated: SQLExpression = Columns.rating != nil
  // notInterested is a "rated" row (so it's excluded from `candidate`) but it
  // contributes no positive or negative signal to the recommendation engine.
  static let hasRatingSignal: SQLExpression = loved || liked || disliked
  static let hasCoverage: SQLExpression = Columns.playbackCoverage != nil
  static let candidate: SQLExpression = unstarted && unfinished && !rated && unqueued
  static let hasEmbedding: SQLExpression =
    EpisodeEmbedding
    .select(EpisodeEmbedding.Columns.episodeId)
    .contains(Columns.id)

  // Each word must match, but a word may land in either the episode's own text
  // or its parent podcast's text — so "tech daily" finds the "Daily" episode of
  // the "Tech" podcast. AND across words, OR across the two FTS mirrors per word.
  static func matchesText(allWordsIn text: String) -> SQLExpression {
    text
      .split(separator: /\s+/)
      .compactMap { FTS5Pattern(matchingAllPrefixesIn: String($0)) }
      .map { pattern in
        EpisodeFTS.matching(pattern).select(Column.rowID).contains(Columns.id)
          || PodcastFTS.matching(pattern).select(Column.rowID).contains(Columns.podcastId)
      }
      .reduce(AppDB.noOp) { $0 && $1 }
  }

  // MARK: - Columns

  enum Columns {
    static let id = Column("id")
    static let podcastId = Column("podcastId")
    static let guid = Column("guid")
    static let mediaURL = Column("mediaURL")
    static let title = Column("title")
    static let pubDate = Column("pubDate")
    static let duration = Column("duration")
    static let description = Column("description")
    static let link = Column("link")
    static let image = Column("image")
    static let finishDate = Column("finishDate")
    static let currentTime = Column("currentTime")
    static let maxPlaybackTime = Column("maxPlaybackTime")
    static let playbackStarted = Column("playbackStarted")
    static let queueOrder = Column("queueOrder")
    static let queueDate = Column("queueDate")
    static let cachedFilename = Column("cachedFilename")
    static let downloading = Column("downloading")
    static let saveInCache = Column("saveInCache")
    static let rating = Column("rating")
    static let ratingDate = Column("ratingDate")
    static let creationDate = Column("creationDate")
    static let contentUpdatedAt = Column("contentUpdatedAt")
    static let playbackCoverage = Column("playbackCoverage")
    static let lastPlayedDate = Column("lastPlayedDate")
    static let transcript = Column("transcript")
  }

  // MARK: - RSSUpdatable

  var rssUpdatableColumns: [(any ColumnExpression, any SQLExpressible)] {
    unsaved.rssUpdatableColumns
  }

  func rssEquals(_ other: Episode) -> Bool {
    unsaved.rssEquals(other.unsaved)
  }

  // MARK: - EpisodeFoundational

  var mediaGUID: MediaGUID { unsaved.mediaGUID }
  var title: String { unsaved.title }
  var pubDate: Date { unsaved.pubDate }
  var description: String? { unsaved.description }
  var duration: CMTime { unsaved.duration }
  var currentTime: CMTime { unsaved.currentTime }
  var maxPlaybackTime: CMTime { unsaved.maxPlaybackTime }
  var queueDate: Date? { unsaved.queueDate }
  var queueOrder: Int? { unsaved.queueOrder }
  var cacheStatus: CacheStatus { unsaved.cacheStatus }
  var saveInCache: Bool { unsaved.saveInCache }
  var finishDate: Date? { unsaved.finishDate }
  var rating: EpisodeRating? { unsaved.rating }
  var ratingDate: Date? { unsaved.ratingDate }

  // MARK: - Derived Passthroughs
  var cachedURL: CachedURL? { unsaved.cachedURL }
  var hasTranscript: Bool { unsaved.hasTranscript }
  var decodedTranscript: Transcript? { unsaved.decodedTranscript }

  // MARK: - Reset

  func toOriginalUnsavedEpisode() throws -> UnsavedEpisode {
    try unsaved.toOriginalUnsavedEpisode()
  }

  // MARK: - Cache Status

  enum CacheStatus: Hashable, Sendable {
    case uncached
    case caching
    case cached

    static func from(
      cachedFilename: String?,
      downloading: Bool
    ) -> CacheStatus {
      if cachedFilename != nil { return .cached }
      if downloading { return .caching }
      return .uncached
    }
  }
}

// MARK: - Chapter Parsing

extension Episode {
  // Parses timestamps (e.g. "2:15", "14:30", "1:02:15") from the description
  // and returns them as sorted CMTimes. Returns nil if none are found.
  static func chapters(from description: String?, duration: CMTime) -> [CMTime]? {
    guard let description else { return nil }

    var seen = Set<Int>()
    let times: [CMTime] = unsafe description.matches(of: Timestamp.regex)
      .compactMap { match in
        guard let totalSeconds = Timestamp.parse(match.output) else { return nil }

        // Skip zero timestamps (episode start) and duplicates.
        guard totalSeconds > 0, seen.insert(totalSeconds).inserted else { return nil }

        // Skip timestamps that exceed the episode duration.
        let time = CMTime.seconds(Double(totalSeconds))
        if time > duration { return nil }

        return time
      }
      .sorted()

    guard !times.isEmpty else { return nil }
    return times
  }
}

// MARK: - DerivableRequest

extension DerivableRequest<Episode> {
  func queued() -> Self {
    filter(Episode.queued)
  }

  func unqueued() -> Self {
    filter(Episode.unqueued)
  }

  func cached() -> Self {
    filter(Episode.cached)
  }
}
