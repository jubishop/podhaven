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
  // any-embedding flag + the raw inputs the engine needs to resolve
  // per-podcast freshness cadence, so a single transaction touching
  // multiple tables produces one rebuild instead of several.
  // `SignalEpisode`'s `databaseSelection` narrows the fetch to the five
  // Episode columns the engine actually reads. The cadence projection
  // splits in two: rows with an explicit cadence (`IS NOT NULL`) project
  // only id + freshnessCadence, and rows where the cadence is nil project
  // their episodes' (podcastId, pubDate) so the engine can infer a cadence
  // lazily — GRDB's column tracking still ignores updates to currentTime,
  // queueOrder, podcast title, etc.
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

      let manualRows = try Row.fetchAll(
        db,
        Podcast
          .filter(Podcast.Columns.freshnessCadence != nil)
          .select(Podcast.Columns.id, Podcast.Columns.freshnessCadence)
      )
      var manualFreshnessCadences = [Podcast.ID: FreshnessCadence](capacity: manualRows.count)
      for row in manualRows {
        let id: Podcast.ID = row[Podcast.Columns.id]
        let cadence: FreshnessCadence = row[Podcast.Columns.freshnessCadence]
        manualFreshnessCadences[id] = cadence
      }

      let pubDateRows = try Row.fetchAll(
        db,
        Episode
          .joining(required: Episode.podcast.filter(Podcast.Columns.freshnessCadence == nil))
          .select(Episode.Columns.podcastId, Episode.Columns.pubDate)
      )
      var inferenceFreshnessPubDates: [Podcast.ID: [Date]] = [:]
      for row in pubDateRows {
        let id: Podcast.ID = row[Episode.Columns.podcastId]
        let pubDate: Date = row[Episode.Columns.pubDate]
        inferenceFreshnessPubDates[id, default: []].append(pubDate)
      }

      return ScoringContextInputs(
        signals: signals,
        signalEmbeddings: signalEmbeddings,
        hasAnyEmbeddings: hasAnyEmbeddings,
        manualFreshnessCadences: manualFreshnessCadences,
        inferenceFreshnessPubDates: inferenceFreshnessPubDates
      )
    }
  }

  // Private Helpers

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
