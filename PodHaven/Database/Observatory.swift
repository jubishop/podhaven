// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB

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

  // MARK: - Public Functions

  func podcasts(
    _ filter: SQLExpression,
    order: SQLOrdering = Episode.Columns.pubDate.desc,
    limit: Int = Int.max
  ) -> AsyncValueObservation<[Podcast]> {
    _observe { db in
      try Podcast
        .all()
        .filter(filter)
        .order(order)
        .limit(limit)
        .fetchAll(db)
    }
  }

  func podcastsWithLatestEpisodeDates(
    _ filter: SQLExpression,
    limit: Int = Int.max
  )
    -> AsyncValueObservation<[PodcastWithLatestEpisodeDates]>
  {
    _observe { db in
      try PodcastWithLatestEpisodeDates
        .all()
        .filter(filter)
        .limit(limit)
        .fetchAll(db)
    }
  }

  func podcastEpisodes(
    filter: SQLExpression,
    order: SQLOrdering = Episode.Columns.pubDate.desc,
    limit: Int = Int.max
  ) -> AsyncValueObservation<[PodcastEpisode]> {
    _observe { db in
      try Episode
        .all()
        .filter(filter)
        .including(required: Episode.podcast)
        .order(order)
        .limit(limit)
        .asRequest(of: PodcastEpisode.self)
        .fetchAll(db)
    }
  }

  func podcastEpisodes(
    _ mediaGUIDs: [MediaGUID],
    order: SQLOrdering = Episode.Columns.pubDate.desc,
    limit: Int = Int.max
  ) -> AsyncValueObservation<[PodcastEpisode]> {
    let mediaGUIDFilters = mediaGUIDs.map { mediaGUID in
      Episode.Columns.guid == mediaGUID.guid && Episode.Columns.media == mediaGUID.media
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

  func queuedPodcastEpisodes() -> AsyncValueObservation<[PodcastEpisode]> {
    podcastEpisodes(
      filter: Episode.queued,
      order: Episode.Columns.queueOrder.asc
    )
  }

  func maxQueuePosition() -> AsyncValueObservation<Int?> {
    _observe { db in
      try Episode
        .select(max(Episode.Columns.queueOrder), as: Int.self)
        .fetchOne(db)
    }
  }

  func podcastSeries(_ podcastID: Podcast.ID) -> AsyncValueObservation<PodcastSeries?> {
    _observe { db in
      try Podcast
        .withID(podcastID)
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchOne(db)
    }
  }

  func podcastEpisode(_ episodeID: Episode.ID) -> AsyncValueObservation<PodcastEpisode?> {
    _observe { db in
      try Episode
        .withID(episodeID)
        .including(required: Episode.podcast)
        .asRequest(of: PodcastEpisode.self)
        .fetchOne(db)
    }
  }

  // Private Helpers

  private func _observe<T: Equatable>(_ block: @escaping @Sendable (Database) throws -> T)
    -> AsyncValueObservation<T>
  {
    ValueObservation.tracking(block)
      .removeDuplicates()
      .values(in: repo.db)
  }
}
