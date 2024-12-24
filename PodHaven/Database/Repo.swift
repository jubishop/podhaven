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

  func updateSeries(
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

  func dequeue(_ episodeID: Int64) async throws {
    try await appDB.db.write { db in
      guard let oldPosition = try _fetchOldPosition(db, for: episodeID) else {
        return
      }

      try Episode.filter(Column("queueOrder") > oldPosition)
        .updateAll(db, Column("queueOrder").set(to: Column("queueOrder") - 1))
      try Episode.filter(id: episodeID)
        .updateAll(db, Column("queueOrder").set(to: nil))
    }
  }

  func insertToQueue(_ episodeID: Int64, at newPosition: Int) async throws {
    try await appDB.db.write { db in
      if let oldPosition = try _fetchOldPosition(db, for: episodeID) {
        try _moveInQueue(db, from: oldPosition, to: newPosition)
      } else {
        try Episode.filter(Column("queueOrder") >= newPosition)
          .updateAll(db, Column("queueOrder").set(to: Column("queueOrder") + 1))
        try Episode
          .filter(id: episodeID)
          .updateAll(db, Column("queueOrder").set(to: newPosition))
      }
    }
  }

  func appendToQueue(_ episodeID: Int64) async throws {
    try await appDB.db.write { db in
      let newPosition =
        (try Episode
          .select(max(Column("queueOrder")), as: Int.self)
          .fetchOne(db) ?? 0) + 1
      if let oldPosition = try _fetchOldPosition(db, for: episodeID) {
        try _moveInQueue(db, from: oldPosition, to: newPosition - 1)
      } else {
        try Episode
          .filter(id: episodeID)
          .updateAll(db, Column("queueOrder").set(to: newPosition))
      }
    }
  }

  //MARK: - Private Helpers

  private func _fetchOldPosition(_ db: Database, for episodeID: Int64) throws
    -> Int?
  {
    precondition(
      db.isInsideTransaction,
      "fetchOldPosition method requires a transaction"
    )

    return
      try Episode
      .filter(id: episodeID)
      .select(Column("queueOrder"), as: Int.self)
      .fetchOne(db)
  }

  private func _moveInQueue(
    _ db: Database,
    from oldPosition: Int,
    to newPosition: Int
  ) throws {
    guard newPosition != oldPosition else { return }
    precondition(
      db.isInsideTransaction,
      "moveInQueue method requires a transaction"
    )
  }
}
