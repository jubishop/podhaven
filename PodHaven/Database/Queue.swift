// Copyright Justin Bishop, 2025

import AVFoundation
import Factory
import Foundation
import GRDB
import IdentifiedCollections
import Tagged

extension Container {
  var queue: Factory<Queue> {
    Factory(self) { Queue(.onDisk(QueueAccessKey())) }.scope(.singleton)
  }
}

struct QueueAccessKey { fileprivate init() {} }

struct Queue: Sendable {
  #if DEBUG
    static func inMemory() -> Queue { Queue(.inMemory()) }
    static func initForTest(_ appDB: AppDB) -> Queue { Queue(appDB) }
  #endif

  // MARK: - Initialization

  private let appDB: AppDB
  fileprivate init(_ appDB: AppDB) {
    self.appDB = appDB
  }

  func clear() async throws {
    _ = try await appDB.db.write { db in
      try Episode.filter(Schema.queueOrderColumn != nil)
        .updateAll(db, Schema.queueOrderColumn.set(to: nil))
    }
  }

  func dequeue(_ episodeID: Episode.ID) async throws {
    try await appDB.db.write { db in
      guard let oldPosition = try _fetchOldPosition(db, for: episodeID)
      else { return }

      try _move (db, episodeID: episodeID, from: oldPosition, to: Int.max)
      try Episode.filter(id: episodeID)
        .updateAll(db, Schema.queueOrderColumn.set(to: nil))
    }
  }

  func insert(_ episodeID: Episode.ID, at newPosition: Int) async throws {
    try await appDB.db.write { db in
      try _insert(db, episodeID: episodeID, at: newPosition)
    }
  }

  func unshift(_ episodeIDs: [Episode.ID]) async throws {
    for episodeID in episodeIDs.reversed() {
      try await appDB.db.write { db in
        try _insert(db, episodeID: episodeID, at: 0)
      }
    }
  }

  func unshift(_ episodeID: Episode.ID) async throws {
    try await unshift([episodeID])
  }

  func append(_ episodeID: Episode.ID) async throws {
    try await appDB.db.write { db in
      let newPosition =
        (try Episode
          .select(max(Schema.queueOrderColumn), as: Int.self)
          .fetchOne(db) ?? -1) + 1
      try _insert(db, episodeID: episodeID, at: newPosition)
    }
  }

  //MARK: - Private Queue Helpers

  private func _fetchOldPosition(_ db: Database, for episodeID: Episode.ID) throws -> Int? {
    precondition(
      db.isInsideTransaction,
      "fetchOldPosition method requires a transaction"
    )
    return
      try Episode
      .filter(id: episodeID)
      .select(Schema.queueOrderColumn, as: Int.self)
      .fetchOne(db)
  }

  private func _insert(
    _ db: Database,
    episodeID: Episode.ID,
    at newPosition: Int
  ) throws {
    precondition(
      db.isInsideTransaction,
      "insertToQueue method requires a transaction"
    )
    let oldPosition = try _fetchOldPosition(db, for: episodeID) ?? Int.max
    let computedNewPosition = newPosition > oldPosition ? newPosition - 1 : newPosition
    try _move (db, episodeID: episodeID, from: oldPosition, to: computedNewPosition)
    try Episode
      .filter(id: episodeID)
      .updateAll(db, Schema.queueOrderColumn.set(to: computedNewPosition))
  }

  private func _move(
    _ db: Database,
    episodeID: Episode.ID,
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
        Schema.queueOrderColumn > oldPosition && Schema.queueOrderColumn <= newPosition
      )
      .updateAll(db, Schema.queueOrderColumn -= 1)
    } else {
      try Episode.filter(
        Schema.queueOrderColumn >= newPosition && Schema.queueOrderColumn < oldPosition
      )
      .updateAll(db, Schema.queueOrderColumn += 1)
    }
  }
}
