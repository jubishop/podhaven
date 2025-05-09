// Copyright Justin Bishop, 2025

import Factory
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

  func allPodcasts(_ sqlExpression: SQLExpression? = nil) -> AsyncValueObservation<[Podcast]> {
    _observe { db in
      try Podcast.all().filtered(with: sqlExpression).fetchAll(db)
    }
  }

  func allPodcastsWithLatestEpisodeDates(_ sqlExpression: SQLExpression? = nil)
    -> AsyncValueObservation<[PodcastWithLatestEpisodeDates]>
  {
    _observe { db in
      try PodcastWithLatestEpisodeDates.all().filtered(with: sqlExpression).fetchAll(db)
    }
  }

  func queuedPodcastEpisodes() -> AsyncValueObservation<[PodcastEpisode]> {
    _observe { db in
      try Episode.all()
        .inQueue()
        .including(required: Episode.podcast)
        .order(Schema.queueOrderColumn.asc)
        .asRequest(of: PodcastEpisode.self)
        .fetchAll(db)
    }
  }

  func completedPodcastEpisodes() -> AsyncValueObservation<[PodcastEpisode]> {
    _observe { db in
      try Episode
        .all()
        .filter(Schema.completedColumn == true)
        .including(required: Episode.podcast)
        .order(Schema.pubDateColumn.desc)
        .asRequest(of: PodcastEpisode.self)
        .fetchAll(db)
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

  func podcastEpisode(_ mediaURL: MediaURL) -> AsyncValueObservation<PodcastEpisode?> {
    _observe { db in
      try Episode
        .filter(Schema.mediaColumn == mediaURL)
        .including(required: Episode.podcast)
        .asRequest(of: PodcastEpisode.self)
        .fetchOne(db)
    }
  }

  func podcastSeries(_ feedURL: FeedURL) -> AsyncValueObservation<PodcastSeries?> {
    _observe { db in
      try Podcast
        .filter(Schema.feedURLColumn == feedURL)
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchOne(db)
    }
  }

  func nextPodcastEpisode() -> AsyncValueObservation<PodcastEpisode?> {
    _observe { db in
      try Episode
        .filter(Schema.queueOrderColumn == 0)
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
