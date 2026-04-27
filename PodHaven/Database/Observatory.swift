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

struct Observatory: Sendable {
  private static let log = Log.as(LogSubsystem.Database.observatory)

  // MARK: - Initialization

  private let repo: any Databasing
  // Manual fanout for partial-listen signals: their underlying columns are
  // excluded from GRDB tracking, so the engine only sees them when this
  // counter bumps. PlayManager fires it at session boundaries.
  private let refreshTrigger: Broadcast<Int>

  fileprivate init(_ repo: any Databasing) {
    self.repo = repo
    self.refreshTrigger = Broadcast<Int>(0)
  }

  func refreshScoringContext() {
    refreshTrigger.update { $0 += 1 }
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

  // Two sources fan in: the narrow rating-only GRDB observation, and
  // `refreshScoringContext()` bumps. Each emission re-fetches the full
  // ScoringContextInputs (rated + partial). Partial-signal columns are
  // never in any tracked region; this is the only path that surfaces them.
  func scoringContextInputs() -> AsyncStream<ScoringContextInputs> {
    AsyncStream { continuation in
      let ratingSource = _ratingObservation()
      let refreshSource = refreshTrigger.stream()
      let db = repo.db

      let task = Task { [refreshSource] in
        await withTaskGroup(of: Void.self) { group in
          group.addTask {
            do {
              for try await _ in ratingSource {
                if Task.isCancelled { return }
                guard
                  let inputs = await Self._fetchScoringContextInputs(db: db)
                else { continue }
                continuation.yield(inputs)
              }
            } catch {
              Self.log.caughtError(
                "scoringContextInputs rating observation failed",
                error
              )
            }
          }
          group.addTask {
            for await _ in refreshSource {
              if Task.isCancelled { return }
              guard
                let inputs = await Self._fetchScoringContextInputs(db: db)
              else { continue }
              continuation.yield(inputs)
            }
          }
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private func _ratingObservation() -> AsyncValueObservation<[SignalEpisode]> {
    _observe { db in
      try SignalEpisode.filter(Episode.rated).fetchAll(db)
    }
  }

  private static func _fetchScoringContextInputs(
    db: any DatabaseReader
  ) async -> ScoringContextInputs? {
    do {
      return try await db.read { db in
        let ratedSignals = try SignalEpisode.filter(Episode.rated).fetchAll(db)
        let partialSignals =
          try PartialSignal
          .filter(Episode.hasCoverage && !Episode.rated)
          .fetchAll(db)

        let signalIDs = ratedSignals.map(\.id) + partialSignals.map(\.id)
        let signalEmbeddings: IdentifiedArray<Episode.ID, EpisodeEmbedding> =
          signalIDs.isEmpty
          ? IdentifiedArray(id: \.episodeId)
          : try EpisodeEmbedding
            .filter(signalIDs.contains(EpisodeEmbedding.Columns.episodeId))
            .fetchIdentifiedArray(db, id: \.episodeId)

        let hasAnyEmbeddings =
          try !signalEmbeddings.isEmpty || EpisodeEmbedding.fetchCount(db) > 0

        return ScoringContextInputs(
          ratedSignals: ratedSignals,
          partialSignals: partialSignals,
          signalEmbeddings: signalEmbeddings,
          hasAnyEmbeddings: hasAnyEmbeddings,
          freshnessCadences: try Self._resolveFreshnessCadences(db)
        )
      }
    } catch {
      log.caughtError("scoringContextInputs fetch failed", error)
      return nil
    }
  }

  // Private Helpers

  // Manual choices win; nil-cadence podcasts get inferred from their
  // pubDates. Podcasts with no episodes and no manual choice are absent.
  fileprivate static func _resolveFreshnessCadences(
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

    // Raw SQL: window functions aren't expressible via the GRDB query builder.
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
      arguments: [FreshnessCadence.inferenceMaxSamples]
    )
    var pubDatesByPodcast = [Podcast.ID: [Date]](capacity: pubDateRows.count)
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
