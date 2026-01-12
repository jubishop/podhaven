// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import Tagged

extension Container {
  internal func makeQueue() -> Queue { Queue(self.appDB()) }

  var queue: Factory<any Queueing> {
    Factory(self) { self.makeQueue() }.scope(.cached)
  }
}

struct Queue: Queueing {
  private static let log = Log.as(LogSubsystem.Database.queue)

  // MARK: - Initialization

  private let appDB: AppDB
  fileprivate init(_ appDB: AppDB) {
    self.appDB = appDB
  }

  // MARK: - Public Functions / Getters

  var nextEpisode: PodcastEpisode? {
    get async throws {
      try await appDB.db.read { db in
        try Episode
          .filter { $0.queueOrder == 0 }
          .including(required: Episode.podcast)
          .asRequest(of: PodcastEpisode.self)
          .fetchOne(db)
      }
    }
  }

  func clear() async throws {
    try await appDB.db.write { db in
      try _clear(db)
    }
  }

  func replace(_ episodeIDs: [Episode.ID]) async throws {
    try await appDB.db.write { db in
      try _clear(db)

      // Note: Since _clear just set all queueOrder to nil,
      // all episodes will be treated as newly queued
      try _updateQueueDate(db, episodeIDs)

      for (index, episodeID) in episodeIDs.enumerated() {
        try _setToPosition(db, episodeID: episodeID, position: index)
      }
    }
  }

  // Public exposure for Repo.deletePodcast()
  func dequeue(_ db: Database, _ episodeIDs: [Episode.ID]) throws {
    try _dequeue(db, episodeIDs)
  }

  func dequeue(_ episodeIDs: [Episode.ID]) async throws {
    try await appDB.db.write { db in
      try dequeue(db, episodeIDs)
    }
  }

  func dequeue(_ episodeID: Episode.ID) async throws {
    try await dequeue([episodeID])
  }

  func insert(_ episodeID: Episode.ID, at newPosition: Int) async throws {
    Self.log.debug("queue: inserting \(episodeID) at position \(newPosition)")

    try await appDB.db.write { db in
      // IMPORTANT: Update queueDate BEFORE inserting.
      try _updateQueueDate(db, [episodeID])

      try _insert(db, episodeID, at: newPosition)
    }
  }

  // Public exposure for Repo.updateSeriesFromFeed()
  func unshift(_ db: Database, _ episodeIDs: [Episode.ID]) throws {
    try _unshift(db, episodeIDs)
  }

  func unshift(_ episodeIDs: [Episode.ID]) async throws {
    try await appDB.db.write { db in
      try unshift(db, episodeIDs)
    }
  }

  func unshift(_ episodeID: Episode.ID) async throws {
    try await unshift([episodeID])
  }

  // Public exposure for Repo.updateSeriesFromFeed()
  func append(_ db: Database, _ episodeIDs: [Episode.ID]) throws {
    try _append(db, episodeIDs)
  }

  func append(_ episodeIDs: [Episode.ID]) async throws {
    try await appDB.db.write { db in
      try append(db, episodeIDs)
    }
  }

  func append(_ episodeID: Episode.ID) async throws {
    try await append([episodeID])
  }

  func updateQueueOrders(_ episodeIDs: [Episode.ID]) async throws {
    Self.log.debug("queue: updating queue orders for \(episodeIDs.count) episodes")

    guard episodeIDs.count > 1 else { return }

    try await appDB.db.write { db in
      // Verify we're reordering the entire queue
      let maxQueueOrder =
        try Episode
        .select(max(Episode.Columns.queueOrder), as: Int.self)
        .fetchOne(db) ?? -1

      guard maxQueueOrder == episodeIDs.count - 1 else {
        throw QueueError.incompleteReorder(
          expected: episodeIDs.count - 1,
          actual: maxQueueOrder
        )
      }

      // Update each episode's queueOrder using GRDB
      for (index, episodeID) in episodeIDs.enumerated() {
        try Episode
          .withID(episodeID)
          .updateAll(db, Episode.Columns.queueOrder.set(to: index))
      }
    }
  }

  func enforceMaxQueueLength() async throws {
    try await appDB.db.write { db in
      try _enforceMaxQueueLength(db)
    }
  }

  // MARK: - Private Helpers

  private func _updateQueueDate(_ db: Database, _ episodeIDs: [Episode.ID]) throws {
    Assert.precondition(db.isInsideTransaction, "updateQueueDate method requires a transaction")

    guard !episodeIDs.isEmpty
    else { return }

    // Only update queueDate for episodes that are not currently queued.
    try Episode
      .withIDs(episodeIDs)
      .unqueued()
      .updateAll(db, Episode.Columns.queueDate.set(to: Date()))
  }

  private func _dequeue(_ db: Database, _ episodeIDs: [Episode.ID]) throws {
    Assert.precondition(db.isInsideTransaction, "dequeue method requires a transaction")

    guard !episodeIDs.isEmpty
    else {
      Self.log.warning("Calling dequeue with empty episodeIDs?")
      return
    }

    Self.log.debug("queue: dequeueing \(episodeIDs)")

    // Remove episodes from queue
    try Episode
      .withIDs(episodeIDs)
      .updateAll(db, Episode.Columns.queueOrder.set(to: nil))

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
    Assert.precondition(db.isInsideTransaction, "fetchOldPosition method requires a transaction")

    return try Episode.withID(episodeID).select(Episode.Columns.queueOrder).fetchOne(db)
  }

  private func _insert(
    _ db: Database,
    _ episodeID: Episode.ID,
    at newPosition: Int
  ) throws {
    Assert.precondition(db.isInsideTransaction, "insert method requires a transaction")

    let oldPosition = try _fetchOldPosition(db, for: episodeID) ?? Int.max
    let computedNewPosition = newPosition > oldPosition ? newPosition - 1 : newPosition
    try _move(db, episodeID, from: oldPosition, to: computedNewPosition)
    try _setToPosition(db, episodeID: episodeID, position: computedNewPosition)
  }

  private func _unshift(_ db: Database, _ episodeIDs: [Episode.ID]) throws {
    Assert.precondition(db.isInsideTransaction, "unshift method requires a transaction")

    guard !episodeIDs.isEmpty
    else {
      Self.log.warning("Calling unshift with empty episodeIDs?")
      return
    }

    Self.log.debug("queue: unshifting \(episodeIDs)")

    // IMPORTANT: Update queueDate BEFORE dequeueing.
    try _updateQueueDate(db, episodeIDs)

    // Remove any existing episodes
    try _dequeue(db, episodeIDs)

    // Make space for the new episodes at the beginning of the queue
    try Episode
      .all()
      .queued()
      .updateAll(db, Episode.Columns.queueOrder += episodeIDs.count)

    // Assign queue positions to the incoming episodes
    for (index, id) in episodeIDs.enumerated() {
      try Episode
        .withID(id)
        .updateAll(db, Episode.Columns.queueOrder.set(to: index))
    }

    // Enforce max queue length by removing from the end
    try _enforceMaxQueueLength(db)
  }

  private func _append(_ db: Database, _ episodeIDs: [Episode.ID]) throws {
    Assert.precondition(db.isInsideTransaction, "append method requires a transaction")

    guard !episodeIDs.isEmpty
    else {
      Self.log.warning("Calling append with empty episodeIDs?")
      return
    }

    Self.log.debug("queue: appending \(episodeIDs)")

    // IMPORTANT: Update queueDate BEFORE dequeueing.
    try _updateQueueDate(db, episodeIDs)

    // Remove any existing episodes
    try _dequeue(db, episodeIDs)

    // Check if adding these episodes would exceed max queue length
    let maxQueueLength = Container.shared.userSettings().maxQueueLength
    let currentCount =
      try Episode
      .all()
      .queued()
      .fetchCount(db)

    // Calculate how many episodes we can add
    let availableSpace = maxQueueLength - currentCount
    guard availableSpace > 0 else {
      Self.log.debug(
        """
        cannot append \(episodeIDs.count) episodes, \
        queue is at max length of \(maxQueueLength)
        """
      )
      return
    }

    // Only append as many episodes as will fit
    let episodesToAppend = Array(episodeIDs.prefix(availableSpace))
    if episodesToAppend.count < episodeIDs.count {
      let skippedCount = episodeIDs.count - episodesToAppend.count
      Self.log.debug(
        """
        appending \(episodesToAppend.count) episodes, \
        skipping \(skippedCount) due to max queue length of \(maxQueueLength)
        """
      )
    }

    // Get the current max position after potential removals
    let maxPosition =
      try Episode
      .select(max(Episode.Columns.queueOrder), as: Int.self)
      .fetchOne(db) ?? -1

    // Assign queue positions to the incoming episodes
    for (index, id) in episodesToAppend.enumerated() {
      try Episode
        .withID(id)
        .updateAll(db, Episode.Columns.queueOrder.set(to: index + maxPosition + 1))
    }
  }

  private func _move(
    _ db: Database,
    _ episodeID: Episode.ID,
    from oldPosition: Int,
    to newPosition: Int
  ) throws {
    guard newPosition != oldPosition else { return }
    Assert.precondition(db.isInsideTransaction, "move method requires a transaction")

    Self.log.debug(
      "queue: moving episode \(episodeID) from position \(oldPosition) to \(newPosition)"
    )

    if newPosition > oldPosition {
      try Episode.filter {
        $0.queueOrder > oldPosition && $0.queueOrder <= newPosition
      }
      .updateAll(db, Episode.Columns.queueOrder -= 1)
    } else {
      try Episode.filter {
        $0.queueOrder >= newPosition && $0.queueOrder < oldPosition
      }
      .updateAll(db, Episode.Columns.queueOrder += 1)
    }
  }

  private func _setToPosition(_ db: Database, episodeID: Episode.ID, position: Int) throws {
    Assert.precondition(db.isInsideTransaction, "setToPosition method requires a transaction")

    try Episode.withID(episodeID).updateAll(db, Episode.Columns.queueOrder.set(to: position))
  }

  private func _enforceMaxQueueLength(_ db: Database) throws {
    Assert.precondition(
      db.isInsideTransaction,
      "enforceMaxQueueLength method requires a transaction"
    )

    let maxQueueLength = Container.shared.userSettings().maxQueueLength

    // Get current queue count
    let currentCount =
      try Episode
      .all()
      .queued()
      .fetchCount(db)

    let episodesToRemove = currentCount - maxQueueLength
    guard episodesToRemove > 0 else { return }

    Self.log.debug(
      """
      enforcing max queue length of \(maxQueueLength), \
      removing \(episodesToRemove) episodes from end
      """
    )

    // Remove from the end (highest queueOrder values)
    let episodeIDsToRemove =
      try Episode
      .all()
      .queued()
      .order(\.queueOrder.desc)
      .limit(episodesToRemove)
      .fetchAll(db)
      .map(\.id)

    // Remove the episodes
    try _dequeue(db, episodeIDsToRemove)
  }

  private func _clear(_ db: Database) throws {
    Assert.precondition(db.isInsideTransaction, "clear method requires a transaction")

    try Episode.all().queued().updateAll(db, Episode.Columns.queueOrder.set(to: nil))
  }
}
