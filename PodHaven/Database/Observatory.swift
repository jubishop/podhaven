// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections

extension Container {
  var observatory: Factory<Observatory> {
    Factory(self) { Observatory(self.repo()) }.scope(.cached)
  }
}

struct Observatory {
  private static let log = Log.as(LogSubsystem.Database.observatory)

  // Cap on pubDates fetched per auto-cadence podcast for inference. Median-gap
  // inference is stable well before this many samples, and the dormancy check
  // only needs the single most recent date — bounds per-rebuild work even for
  // podcasts with thousands of historical episodes.
  private static let inferenceMaxPubDatesPerPodcast = 100

  // MARK: - Initialization

  private let repo: any Databasing
  fileprivate init(_ repo: any Databasing) {
    self.repo = repo
  }

  // MARK: - Podcasts

  func podcasts(_ filter: SQLExpression, limit: Int = Int.max) -> AsyncValueObservation<[Podcast]> {
    _observe { db in
      try Podcast
        .all()
        .filter(filter)
        .limit(limit)
        .fetchAll(db)
    }
  }

  func podcasts(_ feedURLs: [FeedURL], limit: Int = Int.max) -> AsyncValueObservation<[Podcast]> {
    podcasts(
      feedURLs.contains(Podcast.Columns.feedURL),
      limit: limit
    )
  }

  func podcastCounts() -> AsyncValueObservation<PodcastCounts> {
    _observe { db in
      let subscribed = try Podcast.all().subscribed().fetchCount(db)
      let unsubscribed = try Podcast.all().unsubscribed().fetchCount(db)
      let untagged = try Podcast.all().having(Podcast.podcastTags.isEmpty).fetchCount(db)

      return PodcastCounts(
        subscribed: subscribed,
        unsubscribed: unsubscribed,
        untagged: untagged,
        byTag: try Self._podcastCountsByTag(db)
      )
    }
  }

  func podcastsWithEpisodeMetadata(
    _ filter: @escaping PodcastFilter = { $0 },
    limit: Int = Int.max
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<Podcast>]> {
    _observe { db in
      try PodcastWithEpisodeMetadata<Podcast>
        .all(filter)
        .limit(limit)
        .fetchAll(db)
    }
  }

  func podcastsWithEpisodeMetadata(
    _ feedURLs: [FeedURL],
    iTunesIDs: [ITunesPodcastID] = [],
    limit: Int = Int.max
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<Podcast>]> {
    podcastsWithEpisodeMetadata(
      { request in
        var filter = feedURLs.contains(Podcast.Columns.feedURL)
        if !iTunesIDs.isEmpty {
          filter = filter || iTunesIDs.contains(Podcast.Columns.iTunesID)
        }
        return request.filter(filter)
      },
      limit: limit
    )
  }

  // MARK: - Listable Podcasts

  func listablePodcastsWithEpisodeMetadata(
    _ filter: @escaping PodcastFilter = { $0 },
    limit: Int = Int.max
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<ListablePodcast>]> {
    _observe { db in
      try PodcastWithEpisodeMetadata<ListablePodcast>
        .all(filter)
        .limit(limit)
        .fetchAll(db)
    }
  }

  func listablePodcastsWithEpisodeMetadata(
    _ feedURLs: [FeedURL],
    iTunesIDs: [ITunesPodcastID] = [],
    limit: Int = Int.max
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<ListablePodcast>]> {
    listablePodcastsWithEpisodeMetadata(
      { request in
        var filter = feedURLs.contains(Podcast.Columns.feedURL)
        if !iTunesIDs.isEmpty {
          filter = filter || iTunesIDs.contains(Podcast.Columns.iTunesID)
        }
        return request.filter(filter)
      },
      limit: limit
    )
  }

  // MARK: - PodcastEpisodes

  func podcastEpisodes<T: FetchableRecord & Equatable>(
    filter: SQLExpression,
    order: SQLOrdering = Episode.Columns.pubDate.desc,
    limit: Int = Int.max
  ) -> AsyncValueObservation<[T]> {
    _observe { db in
      try Episode
        .all()
        .filter(filter)
        .including(required: Episode.podcast)
        .order(order)
        .limit(limit)
        .asRequest(of: T.self)
        .fetchAll(db)
    }
  }

  func podcastEpisodes<T: FetchableRecord & Equatable>(
    _ mediaGUIDs: [MediaGUID],
    order: SQLOrdering = Episode.Columns.pubDate.desc,
    limit: Int = Int.max
  ) -> AsyncValueObservation<[T]> {
    let mediaGUIDFilters = mediaGUIDs.map { mediaGUID in
      Episode.Columns.guid == mediaGUID.guid && Episode.Columns.mediaURL == mediaGUID.mediaURL
    }
    let combinedFilter = mediaGUIDFilters.reduce(false.sqlExpression) { result, filter in
      result || filter
    }

    return podcastEpisodes(
      filter: combinedFilter,
      order: order,
      limit: limit
    )
  }

  // MARK: - Listable PodcastEpisodes

  func listablePodcastEpisodes(
    filter: SQLExpression,
    order: SQLOrdering = Episode.Columns.pubDate.desc,
    limit: Int = Int.max
  ) -> AsyncValueObservation<[ListablePodcastEpisode]> {
    _observe { db in
      try ListablePodcastEpisode.request(filter: filter, order: order, limit: limit).fetchAll(db)
    }
  }

  // MARK: - Queue

  func queuedPodcastEpisodes(limit: Int = Int.max) -> AsyncValueObservation<
    [ListablePodcastEpisode]
  > {
    listablePodcastEpisodes(
      filter: Episode.queued,
      order: Episode.Columns.queueOrder.asc,
      limit: limit
    )
  }

  // MARK: - Tags

  func tags() -> AsyncValueObservation<IdentifiedArrayOf<Tag>> {
    _observe { db in
      try Tag
        .all()
        .orderedByName()
        .fetchIdentifiedArray(db)
    }
  }

  func podcastCountsByTag() -> AsyncValueObservation<[Tag.ID: Int]> {
    _observe { db in
      try Self._podcastCountsByTag(db)
    }
  }

  // MARK: - On Deck

  func onDeck(_ episodeID: Episode.ID) -> AsyncValueObservation<OnDeck?> {
    _observe { db in
      try OnDeck.request(for: episodeID).fetchOne(db)
    }
  }

  // MARK: - Singular Observations

  func podcastSeries(_ podcastID: Podcast.ID) -> AsyncValueObservation<PodcastSeries?> {
    _observe { db in
      try Podcast
        .withID(podcastID)
        .including(all: Podcast.episodes)
        .including(all: Podcast.tags.order { $0.name.collating(.nocase) })
        .asRequest(of: PodcastSeries.self)
        .fetchOne(db)
    }
  }

  func episode<T: FetchableRecord & Equatable>(
    _ episodeID: Episode.ID
  ) -> AsyncValueObservation<T?> {
    _observe { db in
      try Episode
        .withID(episodeID)
        .including(required: Episode.podcast)
        .asRequest(of: T.self)
        .fetchOne(db)
    }
  }

  // MARK: - Recommendations

  // Composite observation feeding `RecommendationEngine`'s cached
  // `ScoringContext`. One stream covers signals + their embeddings + the
  // any-embedding flag + a per-podcast resolved freshness cadence, so a
  // single transaction touching multiple tables produces one rebuild
  // instead of several. `SignalEpisode`'s `databaseSelection` narrows the
  // fetch to the five Episode columns the engine actually reads. The
  // cadence projection issues two column-narrow queries: one for podcasts
  // with an explicit (`IS NOT NULL`) cadence, and one joining Episode to
  // Podcast for the (podcastId, pubDate) tuples needed to infer a cadence
  // for the rest. Inference happens here so `removeDuplicates` can
  // suppress emissions where pubDate changes don't actually shift the
  // inferred cadence — and GRDB's column tracking still ignores updates
  // to currentTime, queueOrder, podcast title, etc.
  func scoringContextInputs() -> AsyncValueObservation<ScoringContextInputs> {
    _observe { db in
      let signals = try SignalEpisode.filter(Episode.signal).fetchAll(db)

      let signalEmbeddings: IdentifiedArray<Episode.ID, EpisodeEmbedding>
      if signals.isEmpty {
        signalEmbeddings = IdentifiedArray(id: \.episodeId)
      } else {
        let signalIDs = signals.map(\.id)
        signalEmbeddings =
          try EpisodeEmbedding
          .filter(signalIDs.contains(EpisodeEmbedding.Columns.episodeId))
          .fetchIdentifiedArray(db, id: \.episodeId)
      }

      let hasAnyEmbeddings =
        try !signalEmbeddings.isEmpty || EpisodeEmbedding.fetchCount(db) > 0

      return ScoringContextInputs(
        signals: signals,
        signalEmbeddings: signalEmbeddings,
        hasAnyEmbeddings: hasAnyEmbeddings,
        freshnessCadences: try Self._resolveFreshnessCadences(db)
      )
    }
  }

  // Private Helpers

  // Resolves every podcast that has either a manual cadence or any
  // episode pubDates into a single map. Manual choices win; nil-cadence
  // podcasts get `FreshnessCadence.infer(from:)` applied to their
  // pubDates. Podcasts with no episodes and no manual choice are absent —
  // the engine falls back to `FreshnessCadence.default` at scoring time.
  private static func _resolveFreshnessCadences(
    _ db: Database
  ) throws -> [Podcast.ID: FreshnessCadence] {
    let manualRows = try Row.fetchAll(
      db,
      Podcast
        .filter(Podcast.Columns.freshnessCadence != nil)
        .select(Podcast.Columns.id, Podcast.Columns.freshnessCadence)
    )
    var resolved = [Podcast.ID: FreshnessCadence](capacity: manualRows.count)
    for row in manualRows {
      let id: Podcast.ID = row[Podcast.Columns.id]
      let cadence: FreshnessCadence = row[Podcast.Columns.freshnessCadence]
      resolved[id] = cadence
    }

    // Window function isn't expressible via the GRDB query builder, so this
    // one stays in raw SQL. ROW_NUMBER caps each podcast's contribution to
    // its N most recent pubDates — see `inferenceMaxPubDatesPerPodcast`.
    let pubDateRows = try Row.fetchAll(
      db,
      sql: """
        SELECT podcastId, pubDate FROM (
          SELECT
            podcastId,
            pubDate,
            ROW_NUMBER() OVER (PARTITION BY podcastId ORDER BY pubDate DESC) AS rn
          FROM episode
          WHERE podcastId IN (SELECT id FROM podcast WHERE freshnessCadence IS NULL)
        ) WHERE rn <= ?
        """,
      arguments: [inferenceMaxPubDatesPerPodcast]
    )
    var pubDatesByPodcast: [Podcast.ID: [Date]] = [:]
    for row in pubDateRows {
      let id: Podcast.ID = row[Episode.Columns.podcastId]
      let pubDate: Date = row[Episode.Columns.pubDate]
      pubDatesByPodcast[id, default: []].append(pubDate)
    }
    for (id, pubDates) in pubDatesByPodcast {
      resolved[id] = FreshnessCadence.infer(from: pubDates)
    }
    return resolved
  }

  private static func _podcastCountsByTag(_ db: Database) throws -> [Tag.ID: Int] {
    Assert.precondition(db.isInsideTransaction, "_podcastCountsByTag requires a transaction")

    let rows = try Row.fetchAll(
      db,
      PodcastTag
        .select(
          PodcastTag.Columns.tagId,
          count(PodcastTag.Columns.podcastId).forKey("count")
        )
        .group(PodcastTag.Columns.tagId)
    )
    return Dictionary(
      uniqueKeysWithValues: rows.map { row in
        (row[PodcastTag.Columns.tagId] as Tag.ID, row["count"] as Int)
      }
    )
  }

  private func _observe<T: Equatable>(_ block: @escaping @Sendable (Database) throws -> T)
    -> AsyncValueObservation<T>
  {
    ValueObservation.tracking(block)
      .removeDuplicates()
      .values(in: repo.db)
  }
}
