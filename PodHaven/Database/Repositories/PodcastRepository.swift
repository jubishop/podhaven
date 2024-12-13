// Copyright Justin Bishop, 2024

import Foundation
import GRDB

struct PodcastRepository: Sendable {
  #if DEBUG
    static func empty() -> PodcastRepository {
      PodcastRepository(.empty())
    }
  #endif

  static let shared = PodcastRepository(.shared)

  var db: any DatabaseReader { appDatabase.db }
  let observer: SharedValueObservation<[Podcast]>
  private let appDatabase: AppDatabase

  private init(_ appDatabase: AppDatabase) {
    self.appDatabase = appDatabase
    self.observer =
      ValueObservation
      .tracking(Podcast.fetchAll)
      .removeDuplicates()
      .shared(in: appDatabase.db)
  }

  // MARK: - Series Writers

  @discardableResult
  func insertSeries(
    _ unsavedPodcast: UnsavedPodcast,
    unsavedEpisodes: [UnsavedEpisode] = []
  ) async throws -> Podcast {
    try await appDatabase.db.write { db in
      let podcast = try unsavedPodcast.insertAndFetch(db, as: Podcast.self)
      for var unsavedEpisode in unsavedEpisodes {
        unsavedEpisode.podcastId = podcast.id
        try unsavedEpisode.insert(db)
      }
      return podcast
    }
  }

  // MARK: - Podcast Writers

  @discardableResult
  func insert(_ unsavedPodcast: UnsavedPodcast) async throws -> Podcast {
    try await insertSeries(unsavedPodcast)
  }

  func delete(_ podcast: Podcast) async throws -> Bool {
    try await appDatabase.db.write { db in
      try podcast.delete(db)
    }
  }
}
