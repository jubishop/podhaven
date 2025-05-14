// Copyright Justin Bishop, 2025

import AVFoundation
import Factory
import Foundation
import GRDB
import IdentifiedCollections
import Tagged

extension Container {
  var queue: Factory<Queue> {
    Factory(self) { Queue(self.appDB()) }.scope(.cached)
  }
}

struct Queue: Sendable {
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

  func dequeue(_ db: Database, _ episodeIDs: [Episode.ID]) throws {
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
      try _insert(db, episodeID, at: newPosition)
    }
  }

  func unshift(_ episodeIDs: [Episode.ID]) async throws {
    guard !episodeIDs.isEmpty
    else { return }

    try await appDB.db.write { db in
      // Remove any existing episodes
      try _dequeue(db, episodeIDs)

      // Make space for the new episodes at the beginning of the queue
      try Episode
        .all()
        .queued()
        .updateAll(db, Schema.Episode.queueOrder += episodeIDs.count)

      // Assign queue positions to the incoming episodes
      for (index, id) in episodeIDs.enumerated() {
        try Episode
          .filter(Schema.Episode.id == id)
          .updateAll(db, Schema.Episode.queueOrder.set(to: index))
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
      // Remove any existing episodes
      try _dequeue(db, episodeIDs)

      // Get the current max position after potential removals
      let maxPosition =
        try Episode
        .select(max(Schema.Episode.queueOrder), as: Int.self)
        .fetchOne(db) ?? -1

      // Assign queue positions to the incoming episodes
      for (index, id) in episodeIDs.enumerated() {
        try Episode
          .filter(Schema.Episode.id == id)
          .updateAll(db, Schema.Episode.queueOrder.set(to: index + maxPosition + 1))
      }
    }
  }

  func append(_ episodeID: Episode.ID) async throws {
    try await append([episodeID])
  }

  // MARK: - Private Helpers

  private func _dequeue(_ db: Database, _ episodeIDs: [Episode.ID]) throws {
    guard !episodeIDs.isEmpty
    else { return }

    // Remove episodes from queue
    try Episode
      .filter(episodeIDs.contains(Schema.Episode.id))
      .updateAll(db, Schema.Episode.queueOrder.set(to: nil))

    // Renumber remaining episodes
    try db.execute(
      sql: """
          WITH numbered_rows AS (
            SELECT 
              ROW_NUMBER() OVER (ORDER BY queueOrder) - 1 AS new_position,
              id AS episode_id
            FROM episode
            WHERE queueOrder IS NOT NULL
          )
          UPDATE episode
          SET queueOrder = (
            SELECT new_position
            FROM numbered_rows
            WHERE numbered_rows.episode_id = episode.id
          )
          WHERE id IN (
            SELECT episode_id FROM numbered_rows
          )
        """
    )
  }

  private func _fetchOldPosition(_ db: Database, for episodeID: Episode.ID) throws -> Int? {
    guard db.isInsideTransaction
    else { Log.fatal("fetchOldPosition method requires a transaction") }

    return try Episode.withID(episodeID).select(Schema.Episode.queueOrder).fetchOne(db)
  }

  private func _insert(
    _ db: Database,
    _ episodeID: Episode.ID,
    at newPosition: Int
  ) throws {
    guard db.isInsideTransaction
    else { Log.fatal("insertToQueue method requires a transaction") }

    let oldPosition = try _fetchOldPosition(db, for: episodeID) ?? Int.max
    let computedNewPosition = newPosition > oldPosition ? newPosition - 1 : newPosition
    try _move (db, episodeID, from: oldPosition, to: computedNewPosition)
    try _setToPosition(db, episodeID: episodeID, position: computedNewPosition)
  }

  private func _move(
    _ db: Database,
    _ episodeID: Episode.ID,
    from oldPosition: Int,
    to newPosition: Int
  ) throws {
    guard newPosition != oldPosition else { return }
    guard db.isInsideTransaction
    else { Log.fatal("moveInQueue method requires a transaction") }

    if newPosition > oldPosition {
      try Episode.filter(
        Schema.Episode.queueOrder > oldPosition && Schema.Episode.queueOrder <= newPosition
      )
      .updateAll(db, Schema.Episode.queueOrder -= 1)
    } else {
      try Episode.filter(
        Schema.Episode.queueOrder >= newPosition && Schema.Episode.queueOrder < oldPosition
      )
      .updateAll(db, Schema.Episode.queueOrder += 1)
    }
  }

  private func _setToPosition(_ db: Database, episodeID: Episode.ID, position: Int) throws {
    guard db.isInsideTransaction
    else { Log.fatal("setToPosition method requires a transaction") }

    try Episode.withID(episodeID).updateAll(db, Schema.Episode.queueOrder.set(to: position))
  }

  private func _clear(_ db: Database) throws {
    guard db.isInsideTransaction
    else { Log.fatal("clear method requires a transaction") }

    try Episode.all().queued().updateAll(db, Schema.Episode.queueOrder.set(to: nil))
  }
}
