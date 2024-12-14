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

  var db: any DatabaseReader { appDB.db }

  private let appDB: AppDB

  private init(_ appDB: AppDB) {
    self.appDB = appDB
  }

  // MARK: - Series Writers

  @discardableResult
  func insertSeries(
    _ unsavedPodcast: UnsavedPodcast,
    unsavedEpisodes: [UnsavedEpisode] = []
  ) async throws -> Podcast {
    try await appDB.db.write { db in
      let podcast = try unsavedPodcast.insertAndFetch(db, as: Podcast.self)
      for var unsavedEpisode in unsavedEpisodes {
        unsavedEpisode.podcastId = podcast.id
        try unsavedEpisode.insert(db)
      }
      return podcast
    }
  }

  func insertSeries(
    _ podcast: Podcast,
    unsavedEpisodes: [UnsavedEpisode] = [],
    existingEpisodes: [Episode] = []
  ) async throws {
    try await appDB.db.write { db in
      try podcast.update(db)
      for existingEpisode in existingEpisodes {
        try existingEpisode.update(db)
      }
      for var unsavedEpisode in unsavedEpisodes {
        unsavedEpisode.podcastId = podcast.id
        try unsavedEpisode.insert(db)
      }
    }
  }

  // MARK: - Podcast Writers

  @discardableResult
  func insert(_ unsavedPodcast: UnsavedPodcast) async throws -> Podcast {
    try await insertSeries(unsavedPodcast)
  }

  func delete(_ podcast: Podcast) async throws -> Bool {
    try await appDB.db.write { db in
      try podcast.delete(db)
    }
  }
}
