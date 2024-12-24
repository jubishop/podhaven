// Copyright Justin Bishop, 2024

import AVFoundation
import Foundation
import GRDB

struct Repo: Sendable {
  #if DEBUG
    static func empty() -> Repo { Repo(.empty()) }
  #endif

  static let shared = Repo(.shared)

  var db: any DatabaseReader { appDB.db }

  private let appDB: AppDB

  init(_ appDB: AppDB) {
    self.appDB = appDB
  }

  // MARK: - Readers

  func allPodcasts() async throws -> PodcastArray {
    try await appDB.db.read { db in
      try Podcast.all().fetchIdentifiedArray(db, id: \Podcast.feedURL)
    }
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
  func delete(_ podcast: Podcast) async throws -> Bool {
    try await appDB.db.write { db in
      try podcast.delete(db)
    }
  }

  // MARK: - Episode Writers

  func updateCurrentTime(
    _ episodeID: Int64,
    _ currentTime: CMTime
  ) async throws {
    _ = try await appDB.db.write { db in
      try Episode
        .filter(id: episodeID)
        .updateAll(db, Column("currentTime").set(to: currentTime))
    }
  }

  func insertToQueue(_ episodeID: Int64, at position: Int) async throws {
    try await appDB.db.write { db in
      try Episode.filter(Column("queueOrder") >= position)
        .updateAll(db, Column("queueOrder").set(to: Column("queueOrder") + 1))
      try Episode.filter(id: episodeID)
        .updateAll(db, Column("queueOrder").set(to: position))
    }
  }

  func appendToQueue(_ episodeID: Int64) async throws {
    try await appDB.db.write { db in
      let max =
        try Episode
        .select(max(Column("queueOrder")), as: Int.self)
        .fetchOne(db)
      try Episode
        .filter(id: episodeID)
        .updateAll(db, Column("queueOrder").set(to: (max ?? 0) + 1))
    }
  }
}
