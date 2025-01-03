// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import IdentifiedCollections

struct Repo: Sendable {
  #if DEBUG
    static func empty() -> Repo { Repo(.empty()) }
  #endif

  static let shared = Repo(.shared)

  // MARK: - Initialization

  var db: any DatabaseReader { appDB.db }
  private let appDB: AppDB
  init(_ appDB: AppDB) {
    self.appDB = appDB
  }

  // MARK: - Global Readers

  func allPodcasts() async throws -> PodcastArray {
    try await appDB.db.read { db in
      try Podcast.all().fetchIdentifiedArray(db, id: \Podcast.feedURL)
    }
  }

  // MARK: - Series Readers

  func podcastSeries(podcastID: Int64) async throws -> PodcastSeries? {
    try await appDB.db.read { db in
      try Podcast
        .filter(id: podcastID)
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchOne(db)
    }
  }

  // MARK: - Episode Readers

  func nextEpisode() async throws -> PodcastEpisode? {
    try await appDB.db.read { db in
      try Episode
        .filter(AppDB.queueOrderColumn == 0)
        .including(required: Episode.podcast)
        .asRequest(of: PodcastEpisode.self)
        .fetchOne(db)
    }
  }

  func episode(_ episodeID: Int64) async throws -> PodcastEpisode? {
    try await appDB.db.read { db in
      try Episode
        .filter(id: episodeID)
        .including(required: Episode.podcast)
        .asRequest(of: PodcastEpisode.self)
        .fetchOne(db)
    }
  }

  func episode(_ url: URL) async throws -> PodcastEpisode? {
    try await appDB.db.read { db in
      try Episode
        .filter(AppDB.mediaColumn == url)
        .including(required: Episode.podcast)
        .asRequest(of: PodcastEpisode.self)
        .fetchOne(db)
    }
  }

  // MARK: - Series Writers

  @discardableResult
  func insertSeries(_ unsavedPodcast: UnsavedPodcast, unsavedEpisodes: [UnsavedEpisode] = [])
    async throws -> PodcastSeries
  {
    try await appDB.db.write { db in
      let podcast = try unsavedPodcast.insertAndFetch(db, as: Podcast.self)
      var episodes: IdentifiedArray<String, Episode> = IdentifiedArray(
        id: \Episode.guid
      )
      for var unsavedEpisode in unsavedEpisodes {
        unsavedEpisode.podcastId = podcast.id
        episodes.append(try unsavedEpisode.insertAndFetch(db, as: Episode.self))
      }
      return PodcastSeries(podcast: podcast, episodes: episodes)
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

  func updateCurrentTime(_ episodeID: Int64, _ currentTime: CMTime) async throws {
    _ = try await appDB.db.write { db in
      try Episode
        .filter(id: episodeID)
        .updateAll(db, AppDB.currentTimeColumn.set(to: currentTime))
    }
  }

  func markComplete(_ episodeID: Int64) async throws {
    _ = try await appDB.db.write { db in
      try Episode
        .filter(id: episodeID)
        .updateAll(
          db,
          AppDB.completedColumn.set(to: true),
          AppDB.currentTimeColumn.set(to: CMTime.zero)
        )
    }
  }

  // MARK: - Queue Management

  func clearQueue() async throws {
    _ = try await appDB.db.write { db in
      try Episode.filter(AppDB.queueOrderColumn != nil)
        .updateAll(db, AppDB.queueOrderColumn.set(to: nil))
    }
  }

  func dequeue(_ episodeID: Int64) async throws {
    try await appDB.db.write { db in
      guard let oldPosition = try _fetchOldPosition(db, for: episodeID)
      else { return }

      try _moveInQueue(db, episodeID: episodeID, from: oldPosition, to: Int.max)
      try Episode.filter(id: episodeID)
        .updateAll(db, AppDB.queueOrderColumn.set(to: nil))
    }
  }

  func insertToQueue(_ episodeID: Int64, at newPosition: Int) async throws {
    try await appDB.db.write { db in
      try _insertToQueue(db, episodeID: episodeID, at: newPosition)
    }
  }

  func unshiftToQueue(_ episodeID: Int64) async throws {
    try await appDB.db.write { db in
      try _insertToQueue(db, episodeID: episodeID, at: 0)
    }
  }

  func appendToQueue(_ episodeID: Int64) async throws {
    try await appDB.db.write { db in
      let newPosition =
        (try Episode
          .select(max(AppDB.queueOrderColumn), as: Int.self)
          .fetchOne(db) ?? -1) + 1
      try _insertToQueue(db, episodeID: episodeID, at: newPosition)
    }
  }

  //MARK: - Private Queue Helpers

  private func _fetchOldPosition(_ db: Database, for episodeID: Int64) throws -> Int? {
    precondition(
      db.isInsideTransaction,
      "fetchOldPosition method requires a transaction"
    )
    return
      try Episode
      .filter(id: episodeID)
      .select(AppDB.queueOrderColumn, as: Int.self)
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
    let computedNewPosition = newPosition > oldPosition ? newPosition - 1 : newPosition
    try _moveInQueue(
      db,
      episodeID: episodeID,
      from: oldPosition,
      to: computedNewPosition
    )
    try Episode
      .filter(id: episodeID)
      .updateAll(db, AppDB.queueOrderColumn.set(to: computedNewPosition))
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
        AppDB.queueOrderColumn > oldPosition
          && AppDB.queueOrderColumn <= newPosition
      )
      .updateAll(db, AppDB.queueOrderColumn -= 1)
    } else {
      try Episode.filter(
        AppDB.queueOrderColumn >= newPosition
          && AppDB.queueOrderColumn < oldPosition
      )
      .updateAll(db, AppDB.queueOrderColumn += 1)
    }
  }
}
