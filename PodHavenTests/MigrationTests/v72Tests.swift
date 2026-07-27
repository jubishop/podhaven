// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v72 migration tests", .container)
struct V72MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator = Schema.makeMigrator()

  private func defaults() throws -> FakeKeyValueStore {
    try #require(Container.shared.standardDefaults() as? FakeKeyValueStore)
  }

  private func prepareFixture(episodeCount: Int = 3) async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v71")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description
          ) VALUES (
            900, 'https://example.com/v72.xml', 'Queue Migration',
            'https://example.com/v72.jpg', 'Description'
          )
          """
      )
      for index in 0..<episodeCount {
        let episodeID = 1_000 + index
        try db.execute(
          sql: """
            INSERT INTO episode (
              id, podcastId, guid, mediaURL, title, pubDate
            ) VALUES (
              ?, 900, ?, ?, ?, '2026-01-01 00:00:00'
            )
            """,
          arguments: [
            episodeID,
            "v72-\(index)",
            "https://example.com/v72-\(index).mp3",
            "Episode \(index)",
          ]
        )
      }
    }
  }

  private func queuedEpisodeIDs() async throws -> [Int64] {
    try await appDB.unsafeTestDB.read { db in
      try Int64.fetchAll(
        db,
        sql: """
          SELECT episodeId
          FROM episodeTranscriptionQueue
          ORDER BY position
          """
      )
    }
  }

  @Test("v72 imports first-seen valid IDs while preserving the legacy key")
  func importsQueueInFirstSeenOrder() async throws {
    try await prepareFixture()
    let defaults = try defaults()
    defaults.set(
      try JSONEncoder().encode([Int64(1_002), 1_000, 1_002, 9_999, 1_001]),
      forKey: "transcriptionQueue"
    )

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v72")

    #expect(try await queuedEpisodeIDs() == [1_002, 1_000, 1_001])
    #expect(defaults.data(forKey: "transcriptionQueue") != nil)
  }

  @Test("v72 tolerates malformed legacy data")
  func toleratesMalformedQueueData() async throws {
    try await prepareFixture()
    let defaults = try defaults()
    defaults.set(Data("not-json".utf8), forKey: "transcriptionQueue")

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v72")

    #expect(try await queuedEpisodeIDs().isEmpty)
    #expect(defaults.data(forKey: "transcriptionQueue") != nil)
  }

  @Test("v72 preserves oversized legacy queues")
  func preservesOversizedQueue() async throws {
    try await prepareFixture(episodeCount: 101)
    let defaults = try defaults()
    let episodeIDs = (0..<101).map { Int64(1_000 + $0) }
    defaults.set(
      try JSONEncoder().encode(episodeIDs),
      forKey: "transcriptionQueue"
    )

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v72")

    #expect(try await queuedEpisodeIDs() == episodeIDs)
  }

  @Test("v72 queue rows cascade when episodes are deleted")
  func queueRowsCascade() async throws {
    try await prepareFixture()
    let defaults = try defaults()
    defaults.set(
      try JSONEncoder().encode([Int64(1_000), 1_001]),
      forKey: "transcriptionQueue"
    )
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v72")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(sql: "DELETE FROM episode WHERE id = 1000")
    }

    #expect(try await queuedEpisodeIDs() == [1_001])
  }
}
