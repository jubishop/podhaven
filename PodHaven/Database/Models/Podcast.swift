// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import SavedMacro
import Tagged

typealias FeedURL = Tagged<UnsavedPodcast, URL>
typealias PodcastFilter =
  @Sendable (QueryInterfaceRequest<Podcast>) -> QueryInterfaceRequest<Podcast>

struct UnsavedPodcast:
  Identifiable,
  PodcastDisplayable,
  RSSUpdatable,
  Savable,
  Stringable
{
  var id: FeedURL { feedURL }

  static let databaseTableName: String = "podcast"

  // Feed
  let feedURL: FeedURL
  let iTunesID: ITunesPodcastID?
  let title: String
  let image: URL
  let description: String
  let link: URL?

  // User
  let lastUpdate: Date
  let subscriptionDate: Date?
  let defaultPlaybackRate: Double?
  let queueAllEpisodes: QueueAllEpisodes
  let cacheAllEpisodes: CacheAllEpisodes
  let notifyNewEpisodes: Bool

  private static let log = Log.as(LogSubsystem.Database.podcast)

  init(
    feedURL: FeedURL,
    iTunesID: ITunesPodcastID? = nil,
    title: String,
    image: URL,
    description: String,
    link: URL?,
    lastUpdate: Date? = nil,
    subscriptionDate: Date? = nil,
    defaultPlaybackRate: Double? = nil,
    queueAllEpisodes: QueueAllEpisodes = .never,
    cacheAllEpisodes: CacheAllEpisodes = .never,
    notifyNewEpisodes: Bool = false
  ) throws {
    self.feedURL = try feedURL.convertToHTTPSURL()
    self.iTunesID = iTunesID
    self.title = title
    self.image = try image.convertToHTTPSURL()
    self.description = description
    if let link {
      do {
        self.link = try link.convertToHTTPSURL()
      } catch {
        Self.log.caughtError(
          "Invalid link URL '\(link)' for podcast '\(title)'",
          error,
          level: { _ in .info }
        )
        self.link = nil
      }
    } else {
      self.link = nil
    }
    self.lastUpdate = lastUpdate ?? Date.epoch
    self.subscriptionDate = subscriptionDate
    self.defaultPlaybackRate = defaultPlaybackRate
    self.queueAllEpisodes = queueAllEpisodes
    self.cacheAllEpisodes = cacheAllEpisodes
    self.notifyNewEpisodes = notifyNewEpisodes
  }

  // MARK: - Savable

  var toString: String { "(\(feedURL.toString)) - \(title)" }
  var searchableString: String { "\(title) - \(description)" }

  // MARK: - RSSUpdatable

  var rssUpdatableColumns: [(any ColumnExpression, any SQLExpressible)] {
    [
      (Podcast.Columns.feedURL, feedURL),
      (Podcast.Columns.title, title),
      (Podcast.Columns.image, image),
      (Podcast.Columns.description, description),
      (Podcast.Columns.link, link),
    ]
  }

  func rssEquals(_ other: UnsavedPodcast) -> Bool {
    feedURL == other.feedURL
      && title == other.title
      && image == other.image
      && description == other.description
      && link == other.link
  }

  // MARK: - Helpers

  func getOrCreatePodcast() async throws -> Podcast {
    let repo = Container.shared.repo()

    if let existingSeries = try await repo.podcastSeries(
      feedURL,
      iTunesID: iTunesID
    ) {
      return existingSeries.podcast
    }

    // Podcast doesn't exist by our keys, parse feed to discover resolved URL
    let podcastFeed = try await PodcastFeed.parse(feedURL)

    // The parsed feed may have a different feedURL (redirect/itunes:new-feed-url).
    // Check if that resolved URL matches an existing podcast.
    if podcastFeed.updatedFeedURL != feedURL {
      if let existingSeries = try await repo.podcastSeries(
        podcastFeed.updatedFeedURL,
        iTunesID: iTunesID
      ) {
        if existingSeries.podcast.iTunesID == nil, let iTunesID {
          try await repo.updateITunesID(existingSeries.podcast.id, iTunesID: iTunesID)
        }
        return existingSeries.podcast
      }
    }

    let podcastSeries = try await repo.insertSeries(
      try podcastFeed.toUnsavedSeries(iTunesID: iTunesID)
    )
    return podcastSeries.podcast
  }

  // MARK: - Reset

  func toOriginalUnsavedPodcast() throws -> UnsavedPodcast {
    try UnsavedPodcast(
      feedURL: feedURL,
      iTunesID: iTunesID,
      title: title,
      image: image,
      description: description,
      link: link
    )
  }
}

@Saved<UnsavedPodcast>
struct Podcast: PodcastDisplayable, Saved, RSSUpdatable {
  // MARK: - Associations

  static let episodes = hasMany(Episode.self).order(\.pubDate.desc)
  static let podcastTags = hasMany(PodcastTag.self)
  static let tags = hasMany(Tag.self, through: podcastTags, using: PodcastTag.tag).order(\.name)

  // MARK: - SQL Expressions

  static let subscribed: SQLExpression = Columns.subscriptionDate != nil
  static let unsubscribed: SQLExpression = Columns.subscriptionDate == nil
  static func contains(_ pattern: String) -> SQLExpression {
    Columns.title.lowercased.like(pattern) || Columns.description.lowercased.like(pattern)
  }

  // MARK: - PodcastFilters

  static func hasTag(_ tagID: Tag.ID) -> PodcastFilter {
    { $0.joining(required: Podcast.podcastTags.filter(PodcastTag.Columns.tagId == tagID)) }
  }

  // MARK: - Columns

  enum Columns {
    static let id = Column("id")
    static let creationDate = Column("creationDate")
    static let feedURL = Column("feedURL")
    static let iTunesID = Column("iTunesID")
    static let title = Column("title")
    static let image = Column("image")
    static let description = Column("description")
    static let link = Column("link")
    static let lastUpdate = Column("lastUpdate")
    static let subscriptionDate = Column("subscriptionDate")
    static let defaultPlaybackRate = Column("defaultPlaybackRate")
    static let queueAllEpisodes = Column("queueAllEpisodes")
    static let cacheAllEpisodes = Column("cacheAllEpisodes")
    static let notifyNewEpisodes = Column("notifyNewEpisodes")
  }

  // MARK: - RSSUpdatable

  var rssUpdatableColumns: [(any ColumnExpression, any SQLExpressible)] {
    unsaved.rssUpdatableColumns
  }

  func rssEquals(_ other: Podcast) -> Bool {
    unsaved.rssEquals(other.unsaved)
  }

  // MARK: - PodcastDisplayable

  var feedURL: FeedURL { unsaved.feedURL }
  var iTunesID: ITunesPodcastID? { unsaved.iTunesID }
  var image: URL { unsaved.image }
  var title: String { unsaved.title }
  var description: String { unsaved.description }
  var link: URL? { unsaved.link }
  var subscriptionDate: Date? { unsaved.subscriptionDate }
  var defaultPlaybackRate: Double? { unsaved.defaultPlaybackRate }
  var queueAllEpisodes: QueueAllEpisodes { unsaved.queueAllEpisodes }
  var cacheAllEpisodes: CacheAllEpisodes { unsaved.cacheAllEpisodes }
  var notifyNewEpisodes: Bool { unsaved.notifyNewEpisodes }

  // MARK: - Reset

  func toOriginalUnsavedPodcast() throws -> UnsavedPodcast {
    try unsaved.toOriginalUnsavedPodcast()
  }
}

// MARK: - DerivableRequest

extension DerivableRequest<Podcast> {
  func subscribed() -> Self {
    filter(Podcast.subscribed)
  }

  func unsubscribed() -> Self {
    filter(Podcast.unsubscribed)
  }
}
