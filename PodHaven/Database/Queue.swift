// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import Tagged

extension Container {
  var queue: Factory<any Queueing> {
    Factory(self) { self.makeQueue() }.scope(.cached)
  }
}

struct Queue: Queueing {
  private static let log = Log.as(LogSubsystem.Database.queue)

  // MARK: - Initialization

  private let reader: AppDB.Reader
  private let writer: AppDB.Writer
  init(reader: AppDB.Reader, writer: AppDB.Writer) {
    self.reader = reader
    self.writer = writer
  }

  // MARK: - Public Functions / Getters

  var nextEpisode: PodcastEpisode? {
    get async throws {
      try await reader.read { db in
        try Episode
          .filter { $0.queueOrder == 0 }
          .including(required: Episode.podcast)
          .asRequest(of: PodcastEpisode.self)
          .fetchOne(db)
      }
    }
  }

  func clear() async throws {
    try await writer.write { db in
      try _clear(db)
    }
  }

  func replace(_ episodeIDs: [Episode.ID]) async throws {
    try await writer.write { db in
      try _clear(db)

      // _clear nulled queueOrder for every row, so every id here looks newly queued.
      try _updateQueueDate(db, episodeIDs)

      for (index, episodeID) in episodeIDs.enumerated() {
        try _setToPosition(db, episodeID: episodeID, position: index)
      }
    }
  }

  func dequeue(_ db: Database, _ episodeIDs: [Episode.ID]) throws {
    try _dequeue(db, episodeIDs)
  }

  func dequeue(_ episodeIDs: [Episode.ID]) async throws {
    try await writer.write { db in
      try dequeue(db, episodeIDs)
    }
  }

  func dequeue(_ episodeID: Episode.ID) async throws {
    try await dequeue([episodeID])
  }

  func insert(_ episodeID: Episode.ID, at newPosition: Int) async throws {
    Self.log.debug("queue: inserting \(episodeID) at position \(newPosition)")

    try await writer.write { db in
      // IMPORTANT: Update queueDate BEFORE inserting.
      try _updateQueueDate(db, [episodeID])

      try _insert(db, episodeID, at: newPosition)
    }
  }

  func unshift(_ db: Database, _ episodeIDs: [Episode.ID]) throws {
    try _unshift(db, episodeIDs)
  }

  func unshift(_ episodeIDs: [Episode.ID]) async throws {
    try await writer.write { db in
      try unshift(db, episodeIDs)
    }
  }

  func unshift(_ episodeID: Episode.ID) async throws {
    try await unshift([episodeID])
  }

  func append(_ db: Database, _ episodeIDs: [Episode.ID]) throws {
    try _append(db, episodeIDs)
  }

  func append(_ episodeIDs: [Episode.ID]) async throws {
    try await writer.write { db in
      try append(db, episodeIDs)
    }
  }

  func append(_ episodeID: Episode.ID) async throws {
    try await append([episodeID])
  }

  func updateQueueOrders(_ episodeIDs: [Episode.ID]) async throws {
    Self.log.debug("queue: updating queue orders for \(episodeIDs.count) episodes")

    guard episodeIDs.count > 1 else { return }

    try await writer.write { db in
      let maxQueueOrder =
        try Episode
        .select(max(Episode.Columns.queueOrder), as: Int.self)
        .fetchOne(db) ?? -1

      guard maxQueueOrder == episodeIDs.count - 1 else {
        Assert.fatal(
          """
          Queue reordering requires all queued episodes
            Expected max queueOrder: \(episodeIDs.count - 1)
            Actual max queueOrder: \(maxQueueOrder)
          """
        )
      }

      for (index, episodeID) in episodeIDs.enumerated() {
        try Episode
          .withID(episodeID)
          .updateAll(db, Episode.Columns.queueOrder.set(to: index))
      }
    }
  }

  func enforceMaxQueueLength() async throws {
    try await writer.write { db in
      try _enforceMaxQueueLength(db)
    }
  }

  func limitPodcast(_ db: Database, podcastID: Podcast.ID, to limit: Int) throws {
    Assert.precondition(db.isInsideTransaction, "limitPodcast method requires a transaction")

    let excessIDs =
      try Episode
      .all()
      .queued()
      .filter(Episode.Columns.podcastId == podcastID)
      .order(\.pubDate.desc)
      .selectID()
      .fetchAll(db)
      .dropFirst(limit)

    try _dequeue(db, Array(excessIDs))
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
      Self.log.debug("Calling dequeue with empty episodeIDs?")
      return
    }

    Self.log.debug("queue: dequeueing \(episodeIDs)")

    try Episode
      .withIDs(episodeIDs)
      .updateAll(db, Episode.Columns.queueOrder.set(to: nil))

    // Renumber remaining episodes so queueOrder stays a dense 0-based sequence.
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
      Self.log.debug("Calling unshift with empty episodeIDs?")
      return
    }

    Self.log.debug("queue: unshifting \(episodeIDs)")

    // Must update queueDate BEFORE dequeueing — _dequeue clears the rows we'd otherwise key on.
    try _updateQueueDate(db, episodeIDs)
    try _dequeue(db, episodeIDs)

    try Episode
      .all()
      .queued()
      .updateAll(
        db,
        Episode.Columns.queueOrder.set(to: Episode.Columns.queueOrder + episodeIDs.count)
      )

    for (index, id) in episodeIDs.enumerated() {
      try Episode
        .withID(id)
        .updateAll(db, Episode.Columns.queueOrder.set(to: index))
    }

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

    // Must update queueDate BEFORE dequeueing — _dequeue clears the rows we'd otherwise key on.
    try _updateQueueDate(db, episodeIDs)
    try _dequeue(db, episodeIDs)

    let maxQueueLength = Container.shared.userSettings().maxQueueLength
    let currentCount =
      try Episode
      .all()
      .queued()
      .fetchCount(db)

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

    let maxPosition =
      try Episode
      .select(max(Episode.Columns.queueOrder), as: Int.self)
      .fetchOne(db) ?? -1

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
      .updateAll(db, Episode.Columns.queueOrder.set(to: Episode.Columns.queueOrder - 1))
    } else {
      try Episode.filter {
        $0.queueOrder >= newPosition && $0.queueOrder < oldPosition
      }
      .updateAll(db, Episode.Columns.queueOrder.set(to: Episode.Columns.queueOrder + 1))
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

    let episodeIDsToRemove =
      try Episode
      .all()
      .queued()
      .order(\.queueOrder.desc)
      .limit(episodesToRemove)
      .fetchAll(db)
      .map(\.id)

    try _dequeue(db, episodeIDsToRemove)
  }

  private func _clear(_ db: Database) throws {
    Assert.precondition(db.isInsideTransaction, "clear method requires a transaction")

    try Episode.all().queued().updateAll(db, Episode.Columns.queueOrder.set(to: nil))
  }
}
