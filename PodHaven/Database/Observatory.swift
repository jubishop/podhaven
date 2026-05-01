// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections

extension Container {
  internal func makeObservatory() -> Observatory { Observatory(self.repo()) }

  var observatory: Factory<any Observing> {
    Factory(self) { self.makeObservatory() }.scope(.cached)
  }
}

struct Observatory: Observing {
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
        byTag: try _podcastCountsByTag(db)
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
      try _podcastCountsByTag(db)
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

  // GRDB-driven stream. Tracked region: rating columns + episodeEmbedding
  // table + freshness cadences. Playback-path columns (currentTime,
  // playbackCoverage, lastPlayedDate) are deliberately NOT referenced —
  // the closure omits the `PartialSignal` fetch precisely so per-checkpoint
  // `updatePlayback` writes do not wake this observation. Partial-listen
  // data is filled in by the engine's debounced rebuild
  // (`latestScoringContextInputs`) and by its `onDeck` session-boundary
  // handler.
  //
  // The embedding fetch filters by rated-signal IDs; that does not narrow
  // GRDB's tracked region (the whole `episodeEmbedding` table is tracked
  // either way), it just avoids loading partial-signal embeddings the
  // observation will never consume — those land in the rebuild path via
  // `Repo.latestScoringContextInputs()`.
  func scoringContextInputs() -> AsyncValueObservation<ScoringContextInputs> {
    _observe { db in
      let ratedSignals = try SignalEpisode.filter(Episode.rated).fetchAll(db)
      let signalIDs = ratedSignals.map(\.id)
      let signalEmbeddings: IdentifiedArray<Episode.ID, EpisodeEmbedding> =
        signalIDs.isEmpty
        ? IdentifiedArray(id: \.episodeId)
        : try EpisodeEmbedding
          .filter(signalIDs.contains(EpisodeEmbedding.Columns.episodeId))
          .fetchIdentifiedArray(db, id: \.episodeId)

      return ScoringContextInputs(
        ratedSignals: ratedSignals,
        partialSignals: [],
        signalEmbeddings: signalEmbeddings,
        embeddingCount: try EpisodeEmbedding.fetchCount(db),
        freshnessCadences: try Repo.resolveFreshnessCadences(db)
      )
    }
  }

  // MARK: - Private Helpers

  private func _podcastCountsByTag(_ db: Database) throws -> [Tag.ID: Int] {
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
