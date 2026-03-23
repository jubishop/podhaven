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

  func podcastsWithEpisodeMetadata<T: PodcastListable & FetchableRecord>(
    _ filter: @escaping PodcastFilter = { $0 },
    limit: Int = Int.max
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<T>]> {
    _observe { db in
      try PodcastWithEpisodeMetadata<T>
        .all(filter)
        .limit(limit)
        .fetchAll(db)
    }
  }

  func podcastsWithEpisodeMetadata<T: PodcastListable & FetchableRecord>(
    _ feedURLs: [FeedURL],
    iTunesIDs: [ITunesPodcastID] = [],
    limit: Int = Int.max
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<T>]> {
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

  // MARK: - Queue

  func queuedPodcastEpisodes(limit: Int = Int.max) -> AsyncValueObservation<[PodcastEpisode]> {
    podcastEpisodes(
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
