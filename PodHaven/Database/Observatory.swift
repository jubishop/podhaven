// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB

extension Container {
  var observatory: Factory<Observatory> {
    Factory(self) { Observatory(Container.shared.repo()) }.scope(.singleton)
  }
}

struct Observatory {
  #if DEBUG
    static func inMemory() -> Observatory { Observatory(.inMemory()) }
    static func initForTest(_ repo: Repo) -> Observatory { Observatory(repo) }
  #endif

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

  func allPodcastsWithLatestEpisodeDate(_ sqlExpression: SQLExpression? = nil)
    -> AsyncValueObservation<[PodcastWithLatestEpisodeDate]>
  {
    let request = Podcast.all().filtered(with: sqlExpression)
      .annotated(
        with:
          Podcast.episodes
          .filter(Schema.completedColumn == false)
          .max(Schema.pubDateColumn)
          .forKey(PodcastWithLatestEpisodeDate.LatestEpisodeKey)
      )

    return _observe { db in
      try PodcastWithLatestEpisodeDate.fetchAll(db, request)
    }
  }

  func queuedEpisodes() -> AsyncValueObservation<[PodcastEpisode]> {
    _observe { db in
      try Episode
        .filter(Schema.queueOrderColumn != nil)
        .including(required: Episode.podcast)
        .order(Schema.queueOrderColumn.asc)
        .asRequest(of: PodcastEpisode.self)
        .fetchAll(db)
    }
  }

  func podcastSeries(_ podcastID: Podcast.ID) -> AsyncValueObservation<PodcastSeries?> {
    _observe { db in
      try Podcast
        .filter(id: podcastID)
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchOne(db)
    }
  }

  func podcastEpisode(_ episodeID: Episode.ID) -> AsyncValueObservation<PodcastEpisode?> {
    _observe { db in
      try Episode
        .filter(id: episodeID)
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

  // Private Helpers

  private func _observe<T: Equatable>(_ block: @escaping @Sendable (Database) throws -> T)
    -> AsyncValueObservation<T>
  {
    ValueObservation.tracking(block)
      .removeDuplicates()
      .values(in: repo.db)
  }
}
