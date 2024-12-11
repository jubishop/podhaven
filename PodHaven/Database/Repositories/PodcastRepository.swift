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

  // MARK: - Podcast Writers

  @discardableResult
  func insert(_ unsavedPodcast: UnsavedPodcast) async throws -> Podcast {
    try await appDatabase.db.write { db in
      try unsavedPodcast.insertAndFetch(db, as: Podcast.self)
    }
  }

  func update(_ podcast: Podcast) async throws {
    try await appDatabase.db.write { db in
      try podcast.update(db)
    }
  }

  func delete(_ podcast: Podcast) async throws -> Bool {
    try await appDatabase.db.write { db in
      try podcast.delete(db)
    }
  }

  // MARK: - Episode Writers

  @discardableResult
  func insert(_ unsavedEpisode: UnsavedEpisode) async throws -> Episode {
    try await appDatabase.db.write { db in
      try unsavedEpisode.insertAndFetch(db, as: Episode.self)
    }
  }
}
