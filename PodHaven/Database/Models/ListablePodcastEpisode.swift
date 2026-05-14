// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Tagged

struct ListablePodcastEpisode:
  EpisodeListable,
  FetchableRecord,
  Hashable,
  Identifiable,
  Searchable,
  Sendable,
  TableRecord
{
  static let databaseTableName: String = Episode.databaseTableName
  static var databaseSelection: [any SQLSelectable] { ListableEpisode.databaseSelection }

  // MARK: - Associations

  static let podcast = belongsTo(Podcast.self)

  @DynamicInjected(\.repo) private var repo

  // MARK: - Stored Fields

  let core: ListableEpisode
  let feedURL: FeedURL
  let podcastImage: URL
  let podcastTitle: String

  // MARK: - Identifiable

  var id: Episode.ID { core.id }

  // MARK: - Forwarded Episode Fields

  var episodeID: Episode.ID? { id }
  var podcastID: Podcast.ID { core.podcastID }
  var mediaGUID: MediaGUID { core.mediaGUID }
  var title: String { core.title }
  var pubDate: Date { core.pubDate }
  var duration: CMTime { core.duration }
  var queueOrder: Int? { core.queueOrder }
  var cacheStatus: Episode.CacheStatus { core.cacheStatus }
  var saveInCache: Bool { core.saveInCache }
  var currentTime: CMTime { core.currentTime }
  var finishDate: Date? { core.finishDate }
  var rating: EpisodeRating? { core.rating }
  var tagIDs: Set<Tag.ID> { core.tagIDs }
  var episodeImage: URL? { core.episodeImage }
  var creationDate: Date { core.creationDate }
  var queueDate: Date? { core.queueDate }

  // MARK: - EpisodeListable

  var image: URL { core.episodeImage ?? podcastImage }

  // MARK: - Searchable

  var searchableString: String { "\(core.title) - \(podcastTitle)" }

  // MARK: - In-Memory Construction

  // Used by `PodcastDetailViewModel` to fold the parent `Podcast` it already
  // holds together with the slim DB-fetched `ListableEpisode` row.
  init(podcast: Podcast, episode: ListableEpisode) {
    core = episode
    feedURL = podcast.feedURL
    podcastImage = podcast.image
    podcastTitle = podcast.title
  }

  // MARK: - FetchableRecord

  init(row: Row) throws {
    core = try ListableEpisode(row: row)
    guard let podcastRow = row.scopes["podcast"] else {
      Assert.fatal("ListablePodcastEpisode requires podcast scope via including(required:)")
    }
    feedURL = podcastRow[Podcast.Columns.feedURL]
    podcastImage = podcastRow[Podcast.Columns.image]
    podcastTitle = podcastRow[Podcast.Columns.title]
  }

  // MARK: - Joined Podcast Column Selection

  // Columns we read from the joined Podcast row. These can't sit in
  // `databaseSelection` because that controls the *primary* table's columns;
  // the join is narrowed via `Episode.podcast.select(podcastColumns)` below.
  static var podcastColumns: [any SQLSelectable] {
    [
      Podcast.Columns.feedURL,
      Podcast.Columns.image,
      Podcast.Columns.title,
    ]
  }

  static func request(
    filter: SQLExpression,
    order: SQLOrdering = Episode.Columns.pubDate.desc,
    limit: Int = Int.max
  ) -> QueryInterfaceRequest<ListablePodcastEpisode> {
    ListablePodcastEpisode
      .filter(filter)
      .including(required: ListablePodcastEpisode.podcast.select(podcastColumns))
      .order(order)
      .limit(limit)
  }

  func getPodcastEpisode() async throws -> PodcastEpisode {
    guard let podcastEpisode = try await repo.podcastEpisode(id) else {
      Assert.fatal("PodcastEpisode not found for ID \(id)")
    }
    return podcastEpisode
  }

  // MARK: - Hashable / Equatable

  func hash(into hasher: inout Hasher) {
    hasher.combine(core)
    hasher.combine(feedURL)
    hasher.combine(podcastImage)
    hasher.combine(podcastTitle)
  }

  static func == (lhs: ListablePodcastEpisode, rhs: ListablePodcastEpisode) -> Bool {
    lhs.core == rhs.core
      && lhs.feedURL == rhs.feedURL
      && lhs.podcastImage == rhs.podcastImage
      && lhs.podcastTitle == rhs.podcastTitle
  }
}
