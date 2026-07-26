// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v71 migration tests", .container)
struct V71MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    migrator = Schema.makeMigrator()
  }

  private func prepareFixture() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v70")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description
          ) VALUES (
            900, 'https://example.com/v71.xml', 'Queue Migration',
            'https://example.com/v71.jpg', 'Description'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate
          ) VALUES
            (901, 900, 'v71-first', 'https://example.com/v71-first.mp3',
             'First', '2026-01-01 00:00:00'),
            (902, 900, 'v71-second', 'https://example.com/v71-second.mp3',
             'Second', '2026-01-02 00:00:00')
          """
      )
    }
  }

  private func defaults() throws -> FakeKeyValueStore {
    try #require(Container.shared.standardDefaults() as? FakeKeyValueStore)
  }

  @Test("v71 moves valid queued episodes to GRDB in first-seen order")
  func movesQueuedEpisodesInOrder() async throws {
    try await prepareFixture()
    let defaults = try defaults()
    defaults.set(
      try JSONEncoder().encode([Int64(902), 901, 902, 999]),
      forKey: "transcriptionQueue"
    )

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v71")

    try await appDB.unsafeTestDB.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT position, episodeId
          FROM episodeTranscriptionQueue
          ORDER BY position
          """
      )
      #expect(rows.map { $0["episodeId"] as Int64 } == [902, 901])
      let positions = try Int64.fetchAll(
        db,
        sql: """
          SELECT position
          FROM episodeTranscriptionQueue
          ORDER BY position
          """
      )
      #expect(positions.count == 2)
      #expect(positions[0] < positions[1])
    }
    #expect(defaults.data(forKey: "transcriptionQueue") != nil)
  }

  @Test("v71 tolerates malformed legacy queue data")
  func toleratesMalformedQueueData() async throws {
    try await prepareFixture()
    let defaults = try defaults()
    defaults.set(Data("not-json".utf8), forKey: "transcriptionQueue")

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v71")

    let count = try await appDB.unsafeTestDB.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episodeTranscriptionQueue")
    }
    #expect(count == 0)
  }

  @Test("v71 queue rows cascade when episodes are deleted")
  func queueRowsCascade() async throws {
    try await prepareFixture()
    let defaults = try defaults()
    defaults.set(
      try JSONEncoder().encode([Int64(901)]),
      forKey: "transcriptionQueue"
    )
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v71")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(sql: "DELETE FROM episode WHERE id = 901")
    }

    let count = try await appDB.unsafeTestDB.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episodeTranscriptionQueue")
    }
    #expect(count == 0)
  }
}
