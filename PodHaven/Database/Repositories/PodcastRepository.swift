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

  private let appDatabase: AppDatabase

  init(_ appDatabase: AppDatabase) {
    self.appDatabase = appDatabase
  }

  func insertPodcast(_ unsavedPodcast: UnsavedPodcast) throws -> Podcast {
    var podcast: Podcast?
    try appDatabase.write { db in
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

  var db: any GRDB.DatabaseReader {
    appDatabase.reader
  }
}
