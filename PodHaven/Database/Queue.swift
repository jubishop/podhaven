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

  // MARK: - Public Functions

  func clear() async throws {
    try await appDB.db.write { db in
      try _clear(db)
    }
  }

  func replace(_ episodeIDs: [Episode.ID]) async throws {
    try await appDB.db.write { db in
      try _clear(db)

      for (index, episodeID) in episodeIDs.enumerated() {
        try _setToPosition(db, episodeID: episodeID, position: index)
      }
    }
  }

  func dequeue(_ db: Database, _ episodeIDs: [Episode.ID], _ key: RepoAccessKey) throws {
    try _dequeue(db, episodeIDs)
  }

  func dequeue(_ episodeIDs: [Episode.ID]) async throws {
    guard !episodeIDs.isEmpty
    else { return }

    try await appDB.db.write { db in
      try _dequeue(db, episodeIDs)
    }
  }

  func dequeue(_ episodeID: Episode.ID) async throws {
    try await dequeue([episodeID])
  }

  func insert(_ episodeID: Episode.ID, at newPosition: Int) async throws {
    try await appDB.db.write { db in
      try _insert(db, episodeID: episodeID, at: newPosition)
    }
  }

  func unshift(_ episodeIDs: [Episode.ID]) async throws {
    guard !episodeIDs.isEmpty
    else { return }

    try await appDB.db.write { db in
      for episodeID in episodeIDs.reversed() {
        try _insert(db, episodeID: episodeID, at: 0)
      }
    }
  }

  func unshift(_ episodeID: Episode.ID) async throws {
    try await unshift([episodeID])
  }

  func append(_ episodeIDs: [Episode.ID]) async throws {
    guard !episodeIDs.isEmpty
    else { return }

    try await appDB.db.write { db in
      for episodeID in episodeIDs {
        let maxPosition =
          (try Episode
            .select(max(Schema.queueOrderColumn), as: Int.self)
            .fetchOne(db) ?? -1) + 1
        try _insert(db, episodeID: episodeID, at: maxPosition)
      }
    }
  }

  func append(_ episodeID: Episode.ID) async throws {
    try await append([episodeID])
  }

  // MARK: - Private Helpers

  private func _dequeue(_ db: Database, _ episodeIDs: [Episode.ID]) throws {
    precondition(db.isInsideTransaction, "dequeue method requires a transaction")

    guard !episodeIDs.isEmpty
    else { return }

    for episodeID in episodeIDs {
      guard let oldPosition = try _fetchOldPosition(db, for: episodeID)
      else { continue }

      try _move (db, episodeID: episodeID, from: oldPosition, to: Int.max)
      try Episode.withID(episodeID).updateAll(db, Schema.queueOrderColumn.set(to: nil))
    }
  }

  private func _fetchOldPosition(_ db: Database, for episodeID: Episode.ID) throws -> Int? {
    precondition(db.isInsideTransaction, "fetchOldPosition method requires a transaction")

    return try Episode.withID(episodeID).select(Schema.queueOrderColumn).fetchOne(db)
  }

  private func _insert(
    _ db: Database,
    episodeID: Episode.ID,
    at newPosition: Int
  ) throws {
    precondition(db.isInsideTransaction, "insertToQueue method requires a transaction")

    let oldPosition = try _fetchOldPosition(db, for: episodeID) ?? Int.max
    let computedNewPosition = newPosition > oldPosition ? newPosition - 1 : newPosition
    try _move (db, episodeID: episodeID, from: oldPosition, to: computedNewPosition)
    try _setToPosition(db, episodeID: episodeID, position: computedNewPosition)
  }

  private func _move(
    _ db: Database,
    episodeID: Episode.ID,
    from oldPosition: Int,
    to newPosition: Int
  ) throws {
    guard newPosition != oldPosition else { return }
    precondition(db.isInsideTransaction, "moveInQueue method requires a transaction")

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

  private func _setToPosition(_ db: Database, episodeID: Episode.ID, position: Int) throws {
    precondition(db.isInsideTransaction, "setToPosition method requires a transaction")

    try Episode.withID(episodeID).updateAll(db, Schema.queueOrderColumn.set(to: position))
  }

  private func _clear(_ db: Database) throws {
    precondition(db.isInsideTransaction, "clear method requires a transaction")

    try Episode.all().inQueue().updateAll(db, Schema.queueOrderColumn.set(to: nil))
  }
}
