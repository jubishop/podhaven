// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v73 migration tests", .container)
struct V73MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator = Schema.makeMigrator()

  private func defaults() throws -> FakeKeyValueStore {
    try #require(Container.shared.standardDefaults() as? FakeKeyValueStore)
  }

  @Test("v73 removes the legacy key only after the queue import commits")
  func removesLegacyKeyAfterImport() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v71")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description
          ) VALUES (
            900, 'https://example.com/v73.xml', 'Queue Cleanup',
            'https://example.com/v73.jpg', 'Description'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate
          ) VALUES (
            1000, 900, 'v73', 'https://example.com/v73.mp3',
            'Episode', '2026-01-01 00:00:00'
          )
          """
      )
    }
    let defaults = try defaults()
    defaults.set(
      try JSONEncoder().encode([Int64(1_000)]),
      forKey: "transcriptionQueue"
    )

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v72")
    #expect(defaults.data(forKey: "transcriptionQueue") != nil)

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v73")
    #expect(defaults.data(forKey: "transcriptionQueue") == nil)
    let queuedEpisodeIDs = try await appDB.unsafeTestDB.read { db in
      try Int64.fetchAll(
        db,
        sql: """
          SELECT episodeId
          FROM episodeTranscriptionQueue
          ORDER BY position
          """
      )
    }
    #expect(queuedEpisodeIDs == [1_000])
  }

  @Test("v73 cleans up malformed legacy data after v72 safely commits")
  func removesMalformedLegacyKey() throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v71")
    let defaults = try defaults()
    defaults.set(Data("not-json".utf8), forKey: "transcriptionQueue")

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v72")
    #expect(defaults.data(forKey: "transcriptionQueue") != nil)

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v73")
    #expect(defaults.data(forKey: "transcriptionQueue") == nil)
  }
}
