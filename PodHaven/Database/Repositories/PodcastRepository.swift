// Copyright Justin Bishop, 2024

import Foundation
import GRDB

struct PodcastRepository: Sendable {
  #if DEBUG
    static func empty() -> PodcastRepository {
      PodcastRepository(.empty())
    }
  #endif

  static let shared: PodcastRepository = {
    PodcastRepository(.shared)
  }()

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
  func insert(_ unsavedPodcast: UnsavedPodcast) throws -> Podcast {
    try appDatabase.db.write { db in
      try unsavedPodcast.insertAndFetch(db, as: Podcast.self)
    }
  }

  func update(_ podcast: Podcast) throws {
    try appDatabase.db.write { db in
      try podcast.update(db)
    }
  }

  func delete(_ podcast: Podcast) throws -> Bool {
    try appDatabase.db.write { db in
      try podcast.delete(db)
    }
  }

  // MARK: - Episode Writers

  @discardableResult
  func insert(_ unsavedEpisode: UnsavedEpisode) throws -> Episode {
    try appDatabase.db.write { db in
      try unsavedEpisode.insertAndFetch(db, as: Episode.self)
    }
  }
}
