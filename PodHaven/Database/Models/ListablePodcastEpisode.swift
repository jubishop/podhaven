// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Tagged

// Lightweight episode+podcast type for list views. Embeds a `ListableEpisode`
// for the Episode-side fields (column list, correlated tag-IDs subquery, row
// decode all live there) and layers on the joined Podcast columns this list
// shape needs — feedURL/title/image. Episode-side reads are surfaced via
// explicit forwarders below (see comment on the forwarder block) so call
// sites that read e.g. `.title`, `.duration`, `.tagIDs` keep working
// unchanged.
//
// `TableRecord` rooted in the Episode table with `databaseSelection` set to
// just the listable Episode columns means any GRDB query rooted in
// `ListablePodcastEpisode` (e.g. `ListablePodcastEpisode.filter(...).fetchAll(db)`)
// gets the column narrowing automatically. The joined Podcast columns still
// need an explicit `.select(podcastColumns)` because they live behind the
// `belongsTo` association.
struct ListablePodcastEpisode:
  EpisodeListable, Searchable, FetchableRecord, TableRecord, Identifiable, Hashable, Sendable
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

  // Plain computed-property forwarders (rather than `@dynamicMemberLookup`)
  // because Swift won't accept dynamic-member lookups as proof of a
  // protocol property requirement, and the call sites benefit from the
  // explicit surface anyway. `tagIDs`, `episodeImage`, `creationDate`, and
  // `queueDate` are surfaced because external callers (notifications,
  // sort/filter helpers, widgets) read them directly.
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

  // Resolves the row's image, falling back to the podcast image so callers
  // never see the optional core value directly.
  var image: URL { core.episodeImage ?? podcastImage }

  // MARK: - Searchable

  var searchableString: String { "\(core.title) - \(podcastTitle)" }

  // MARK: - In-Memory Construction

  // Used by `PodcastDetailViewModel` to fold the parent `Podcast` it already
  // holds together with the slim DB-fetched `ListableEpisode` row, avoiding
  // a redundant podcast join per child.
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

  // Manual conformances are required because `@DynamicInjected` adds a
  // non-Hashable backing storage to the type. We hash and compare only the
  // four stored data fields — `core` is itself Hashable so it carries every
  // Episode-side column for free.
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
