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
  private let appDatabase: AppDatabase

  private init(_ appDatabase: AppDatabase) {
    self.appDatabase = appDatabase
  }

  // MARK: - Podcast Methods

  func insert(_ unsavedPodcast: UnsavedPodcast) throws -> Podcast {
    var podcast: Podcast?
    try appDatabase.db.write { db in
      podcast = try unsavedPodcast.insertAndFetch(db, as: Podcast.self)
    }
    guard let podcast = podcast else {
      throw DatabaseError(
        resultCode: .SQLITE_ERROR,
        message: "Failed to insert podcast: \(unsavedPodcast)"
      )
    }
    return podcast
  }

  func update(_ podcast: Podcast) throws {
    try appDatabase.db.write { db in
      try podcast.update(db)
    }
  }

  func delete(_ podcast: Podcast) throws -> Bool {
    var success: Bool = false
    try appDatabase.db.write { db in
      success = try podcast.delete(db)
    }
    return success
  }
}
