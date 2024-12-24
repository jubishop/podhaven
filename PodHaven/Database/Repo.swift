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

  // MARK: - Queue Management

  func dequeue(_ episodeID: Int64) async throws {
    try await appDB.db.write { db in
      guard let oldPosition = try _fetchOldPosition(db, for: episodeID) else {
        return
      }

      try _moveInQueue(db, episodeID: episodeID, from: oldPosition, to: Int.max)
      try Episode.filter(id: episodeID)
        .updateAll(db, queueColumn.set(to: nil))
    }
  }

  func insertToQueue(_ episodeID: Int64, at newPosition: Int) async throws {
    try await appDB.db.write { db in
      try _insertToQueue(db, episodeID: episodeID, at: newPosition)
    }
  }

  func appendToQueue(_ episodeID: Int64) async throws {
    try await appDB.db.write { db in
      let newPosition =
        (try Episode
          .select(max(queueColumn), as: Int.self)
          .fetchOne(db) ?? 0) + 1
      try _insertToQueue(db, episodeID: episodeID, at: newPosition)
    }
  }

  //MARK: - Private Queue Helpers

  private let queueColumn = Column("queueOrder")

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
      .select(queueColumn, as: Int.self)
      .fetchOne(db)
  }

  private func _insertToQueue(
    _ db: Database,
    episodeID: Int64,
    at newPosition: Int
  ) throws {
    precondition(
      db.isInsideTransaction,
      "insertToQueue method requires a transaction"
    )
    let oldPosition = try _fetchOldPosition(db, for: episodeID) ?? Int.max
    try _moveInQueue(
      db,
      episodeID: episodeID,
      from: oldPosition,
      to: newPosition > oldPosition ? newPosition - 1 : newPosition
    )
    try Episode
      .filter(id: episodeID)
      .updateAll(db, queueColumn.set(to: newPosition))
  }

  private func _moveInQueue(
    _ db: Database,
    episodeID: Int64,
    from oldPosition: Int,
    to newPosition: Int
  ) throws {
    guard newPosition != oldPosition else { return }
    precondition(
      db.isInsideTransaction,
      "moveInQueue method requires a transaction"
    )

    if newPosition > oldPosition {
      try Episode.filter(
        queueColumn > oldPosition && queueColumn <= newPosition
      )
      .updateAll(db, queueColumn.set(to: queueColumn - 1))
    } else {
      try Episode.filter(
        queueColumn >= newPosition && queueColumn < oldPosition
      )
      .updateAll(db, queueColumn.set(to: queueColumn + 1))
    }
  }
}
