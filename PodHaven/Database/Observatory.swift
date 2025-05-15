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
  // MARK: - Initialization

  private let repo: Repo
  fileprivate init(_ repo: Repo) {
    self.repo = repo
  }

  // MARK: - Public Functions

  func allPodcasts(_ filter: SQLExpression = AppDB.NoOp) -> AsyncValueObservation<[Podcast]> {
    _observe { db in
      try Podcast.all().filter(filter).fetchAll(db)
    }
  }

  func allPodcastsWithLatestEpisodeDates(_ filter: SQLExpression = AppDB.NoOp)
    -> AsyncValueObservation<[PodcastWithLatestEpisodeDates]>
  {
    _observe { db in
      try PodcastWithLatestEpisodeDates.all().filter(filter).fetchAll(db)
    }
  }

  func podcastEpisodes(filter: SQLExpression, order: SQLOrdering = Episode.Columns.pubDate.desc)
    -> AsyncValueObservation<[PodcastEpisode]>
  {
    _observe { db in
      try Episode
        .all()
        .filter(filter)
        .including(required: Episode.podcast)
        .order(order)
        .asRequest(of: PodcastEpisode.self)
        .fetchAll(db)
    }
  }

  func queuedPodcastEpisodes() -> AsyncValueObservation<[PodcastEpisode]> {
    podcastEpisodes(
      filter: Episode.queued,
      order: Episode.Columns.queueOrder.asc
    )
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

  func podcastEpisode(_ mediaURL: MediaURL) -> AsyncValueObservation<PodcastEpisode?> {
    _observe { db in
      try Episode
        .filter { $0.media == mediaURL }
        .including(required: Episode.podcast)
        .asRequest(of: PodcastEpisode.self)
        .fetchOne(db)
    }
  }

  func podcastSeries(_ feedURL: FeedURL) -> AsyncValueObservation<PodcastSeries?> {
    _observe { db in
      try Podcast
        .filter { $0.feedURL == feedURL }
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchOne(db)
    }
  }

  func nextPodcastEpisode() -> AsyncValueObservation<PodcastEpisode?> {
    _observe { db in
      try Episode
        .filter { $0.queueOrder == 0 }
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
