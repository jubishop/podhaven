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
        byTag: try _tagCounts(
          PodcastTag.self,
          tagIdColumn: PodcastTag.Columns.tagId,
          countingColumn: PodcastTag.Columns.podcastId,
          in: db
        )
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
      try _tagCounts(
        PodcastTag.self,
        tagIdColumn: PodcastTag.Columns.tagId,
        countingColumn: PodcastTag.Columns.podcastId,
        in: db
      )
    }
  }

  func episodeCountsByTag() -> AsyncValueObservation<[Tag.ID: Int]> {
    _observe { db in
      try _tagCounts(
        EpisodeTag.self,
        tagIdColumn: EpisodeTag.Columns.tagId,
        countingColumn: EpisodeTag.Columns.episodeId,
        in: db
      )
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

  func podcastEpisodeWithTags(_ episodeID: Episode.ID)
    -> AsyncValueObservation<PodcastEpisodeWithTags?>
  {
    _observe { db in
      try Episode
        .withID(episodeID)
        .including(required: Episode.podcast)
        .including(all: Episode.tags.order { $0.name.collating(.nocase) })
        .asRequest(of: PodcastEpisodeWithTags.self)
        .fetchOne(db)
    }
  }

  // MARK: - Recommendations

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
    _observe { db in
      try RecommendationRepo.scoringContextInputs(db)
    }
  }

  // Wakes when any column that gates `Episode.candidate` flips: `rating`,
  // `finishDate`, or `queueOrder`. Used by the recommendation engine to
  // re-rank when an episode leaves or rejoins the candidate pool — e.g.
  // user marks an unrated episode finished, or queues/dequeues an episode.
  //
  // `currentTime` is intentionally excluded from the predicate. GRDB
  // tracks observations by table+column, not by predicate value, so
  // referencing `Episode.started` (which is `currentTime > 0`) would put
  // the entire `currentTime` column into the tracked region — every
  // playback tick (~every couple seconds) would re-run the ID-set query
  // even though `.removeDuplicates()` would suppress the emission. The
  // realistic transitions are still covered:
  //   - `unstarted → started`: starting playback flips `onDeck`, which
  //     the engine's `onDeck` observer turns into a rebuild.
  //   - `started → unstarted` (via finish): `markFinished` writes
  //     `finishDate` and `currentTime = 0` in the same transaction, so
  //     the `finishDate` flip alone wakes this observation.
  //
  // The result is the ID set of episodes currently excluded by any of
  // those three columns. Returning IDs (not counts) is what makes the
  // simultaneous-flip case fire: if one episode is queued while another is
  // dequeued in the same transaction, the count is unchanged but the set
  // membership is, so `.removeDuplicates()` no longer drops the emission.
  func candidateGateExclusions() -> AsyncValueObservation<Set<Episode.ID>> {
    _observe { db in
      try Episode
        .filter(Episode.rated || Episode.finished || Episode.queued)
        .select(Episode.Columns.id, as: Episode.ID.self)
        .fetchSet(db)
    }
  }

  // MARK: - Private Helpers

  private static let countKey = "count"

  private func _tagCounts<T: TableRecord>(
    _ type: T.Type,
    tagIdColumn: Column,
    countingColumn: Column,
    in db: Database
  ) throws -> [Tag.ID: Int] {
    Assert.precondition(db.isInsideTransaction, "_tagCounts requires a transaction")

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

  private func _observe<T: Equatable>(_ block: @escaping @Sendable (Database) throws -> T)
    -> AsyncValueObservation<T>
  {
    ValueObservation.tracking(block)
      .removeDuplicates()
      .values(in: repo.db)
  }
}
