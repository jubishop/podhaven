// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections

extension Container {
  internal func makeObservatory() -> Observatory { Observatory(self.appDB().reader) }

  var observatory: Factory<any Observing> {
    Factory(self) { self.makeObservatory() }.scope(.cached)
  }
}

struct Observatory: Observing {
  private static let log = Log.as(LogSubsystem.Database.observatory)

  // MARK: - Initialization

  private let reader: AppDB.Reader
  fileprivate init(_ reader: AppDB.Reader) {
    self.reader = reader
  }

  // MARK: - Podcasts

  func podcasts(_ filter: SQLExpression, limit: Int = Int.max) -> AsyncValueObservation<[Podcast]> {
    reader.observe { db in
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
    reader.observe { db in
      let subscribed = try Podcast.all().subscribed().fetchCount(db)
      let unsubscribed = try Podcast.all().unsubscribed().fetchCount(db)
      let untagged = try Podcast.all().having(Podcast.podcastTags.isEmpty).fetchCount(db)

      // Per-setting buckets count every podcast regardless of subscription,
      // matching the untagged/per-tag counts above.
      func count(_ predicate: SQLExpression) throws -> Int {
        try Podcast.all().filter(predicate).fetchCount(db)
      }

      var byFreshnessCadence: [FreshnessCadence: Int] = [:]
      for cadence in FreshnessCadence.allCases {
        let cadenceCount = try count(Podcast.resolvedFreshnessCadence(cadence))
        if cadenceCount > 0 { byFreshnessCadence[cadence] = cadenceCount }
      }

      return PodcastCounts(
        subscribed: subscribed,
        unsubscribed: unsubscribed,
        untagged: untagged,
        byTag: try tagCounts(
          PodcastTag.self,
          tagIdColumn: PodcastTag.Columns.tagId,
          countingColumn: PodcastTag.Columns.podcastId,
          in: db
        ),
        byFreshnessCadence: byFreshnessCadence,
        queueOnTop: try count(Podcast.queuesAllEpisodes(.onTop)),
        queueOnBottom: try count(Podcast.queuesAllEpisodes(.onBottom)),
        autoCache: try count(Podcast.cachesAllEpisodes(.cache)),
        autoSave: try count(Podcast.cachesAllEpisodes(.save)),
        notifyNewEpisodes: try count(Podcast.notifiesNewEpisodes)
      )
    }
  }

  func podcastsWithEpisodeMetadata(
    _ filter: @escaping PodcastFilter = { $0 },
    limit: Int = Int.max
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<Podcast>]> {
    reader.observe { db in
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
    reader.observe { db in
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

  // MARK: - Listable PodcastEpisodes

  func listablePodcastEpisodes(
    filter: SQLExpression,
    order: SQLOrdering? = nil,
    limit: Int = Int.max
  ) -> AsyncValueObservation<[ListablePodcastEpisode]> {
    reader.observe { db in
      try ListablePodcastEpisode
        .request(filter: filter, order: order, limit: limit)
        .fetchAll(db)
    }
  }

  // MARK: - Episodes

  // Bare matching IDs, skipping row hydration and the podcast join, for callers
  // that only need membership rather than displayable rows.
  func episodeIDs(filter: SQLExpression) -> AsyncValueObservation<[Episode.ID]> {
    reader.observe { db in
      try Episode
        .filter(filter)
        .select(Episode.Columns.id, as: Episode.ID.self)
        .fetchAll(db)
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
    reader.observe { db in
      try Tag
        .all()
        .orderedByName()
        .fetchIdentifiedArray(db)
    }
  }

  func podcastCountsByTag() -> AsyncValueObservation<[Tag.ID: Int]> {
    reader.observe { db in
      try tagCounts(
        PodcastTag.self,
        tagIdColumn: PodcastTag.Columns.tagId,
        countingColumn: PodcastTag.Columns.podcastId,
        in: db
      )
    }
  }

  func episodeCountsByTag() -> AsyncValueObservation<[Tag.ID: Int]> {
    reader.observe { db in
      try tagCounts(
        EpisodeTag.self,
        tagIdColumn: EpisodeTag.Columns.tagId,
        countingColumn: EpisodeTag.Columns.episodeId,
        in: db
      )
    }
  }

  // MARK: - Smart Lists

  func smartLists() -> AsyncValueObservation<[SmartList]> {
    reader.observe { db in
      try SmartList.all().orderedByDisplay().fetchAll(db)
    }
  }

  func smartList(_ id: SmartList.ID) -> AsyncValueObservation<SmartList?> {
    reader.observe { db in
      try SmartList.withID(id).fetchOne(db)
    }
  }

  // MARK: - On Deck

  func onDeck(_ episodeID: Episode.ID) -> AsyncValueObservation<OnDeck?> {
    reader.observe { db in
      try OnDeck.request(for: episodeID).fetchOne(db)
    }
  }

  // MARK: - Singular Observations

  func podcastSeriesDetail(_ podcastID: Podcast.ID)
    -> AsyncValueObservation<PodcastSeriesDetail?>
  {
    reader.observe { db in
      try PodcastSeriesDetail.fetchOne(podcastID, in: db)
    }
  }

  func podcastEpisodeWithTags(_ episodeID: Episode.ID)
    -> AsyncValueObservation<PodcastEpisodeWithTags?>
  {
    reader.observe { db in
      try Episode
        .withID(episodeID)
        .including(required: Episode.podcast)
        .including(all: Episode.tags.order { $0.name.collating(.nocase) })
        .asRequest(of: PodcastEpisodeWithTags.self)
        .fetchOne(db)
    }
  }

  // MARK: - Recommendations

  // Tracked region: the caller's filter + the embedding join over the slim
  // (id, podcastId, pubDate) projection. Membership filters (`Episode.candidate`,
  // `Episode.started`) read the boundary-flipped `playbackStarted` flag, so
  // per-checkpoint `updatePlayback` writes do not wake this observation.
  func embeddedCandidateEpisodes(filter: SQLExpression) -> AsyncValueObservation<[CandidateEpisode]>
  {
    reader.observe { db in
      try CandidateEpisode
        .joining(required: CandidateEpisode.podcast)
        .filter(filter && Episode.hasEmbedding)
        .fetchAll(db)
    }
  }

  // GRDB-driven stream. Tracked region: rating columns + episodeEmbedding
  // table + freshness cadences. Playback-path columns (currentTime,
  // playbackCoverage, lastPlayedDate) are deliberately NOT referenced — the
  // observation omits the `PartialSignal` fetch (by passing the default
  // empty closure to `RecommendationRepo.scoringContextInputs(_:partialSignals:)`)
  // precisely so per-checkpoint `updatePlayback` writes do not wake this
  // observation. Partial-listen data lands in the engine via the debounced
  // rebuild (`RecommendationRepo.allScoringContextInputs()`) and the `onDeck`
  // session-boundary handler.
  func scoringContextInputsWithoutPartialSignals()
    -> AsyncValueObservation<ScoringContextInputs>
  {
    reader.observe { db in
      try RecommendationRepo.scoringContextInputs(db)
    }
  }

  // Region is just `episode.contentUpdatedAt` + `podcast.contentUpdatedAt`, so
  // playback-path writes (`updatePlayback`) never wake it. `EmbeddingProcessor`
  // debounces each emission and runs the expensive `episodesNeedingEmbeddings`
  // scan once per burst, off the database writer.
  func embeddingWorkSignal() -> AsyncValueObservation<EmbeddingWorkSignal> {
    reader.observe { db in
      let latestEpisode =
        try Episode
        .select(max(Episode.Columns.contentUpdatedAt), as: Date.self)
        .fetchOne(db)
      let latestPodcast =
        try Podcast
        .select(max(Podcast.Columns.contentUpdatedAt), as: Date.self)
        .fetchOne(db)
      return EmbeddingWorkSignal(
        latestEpisodeContentUpdate: latestEpisode,
        latestPodcastContentUpdate: latestPodcast
      )
    }
  }

  // MARK: - Private Helpers

  private static let countKey = "count"

  private func tagCounts<T: TableRecord>(
    _ type: T.Type,
    tagIdColumn: Column,
    countingColumn: Column,
    in db: Database
  ) throws -> [Tag.ID: Int] {
    Assert.precondition(db.isInsideTransaction, "tagCounts requires a transaction")

    let rows = try Row.fetchAll(
      db,
      type
        .select(tagIdColumn, count(countingColumn).forKey(Self.countKey))
        .group(tagIdColumn)
    )
    return Dictionary(
      uniqueKeysWithValues: rows.map { row in
        (row[tagIdColumn] as Tag.ID, row[Self.countKey] as Int)
      }
    )
  }
}
