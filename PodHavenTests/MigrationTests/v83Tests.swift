// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v83 migration tests", .container)
struct V83MigrationTests {
  @Test("upgrade keeps downloads, clears legacy analyses and failures, and inherits protection")
  func upgrade() async throws {
    let appDB = AppDB.inMemory(migrate: false)
    let migrator = Schema.makeMigrator()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v82")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (id, feedURL, title, image, description, silenceMode)
          VALUES (830, 'https://example.com/v83.xml', 'Protection', 'https://example.com/v83.jpg', 'Description', 'balanced');
          INSERT INTO cachedAudioContent (filename, generation, detectorVersion, analysis, failureCount)
          VALUES ('legacy.mp3', 'original', 1, X'00', 2), ('pending.mp3', 'pending', NULL, NULL, 2);
          """
      )
    }
    try migrator.migrate(appDB.unsafeTestDB)
    try await appDB.unsafeTestDB.write { db in
      #expect(
        try String.fetchOne(db, sql: "SELECT quietAudioProtection FROM podcast WHERE id = 830")
          == nil
      )
      #expect(
        try String.fetchOne(db, sql: "SELECT silenceMode FROM podcast WHERE id = 830") == "balanced"
      )
      #expect(
        try Int.fetchOne(
          db,
          sql:
            "SELECT COUNT(*) FROM cachedAudioContent WHERE detectorVersion = 2 AND analysis IS NULL AND failureCount = 0"
        ) == 2
      )
      #expect(
        try String.fetchOne(
          db,
          sql: "SELECT generation FROM cachedAudioContent WHERE filename = 'legacy.mp3'"
        ) == "original"
      )
      for choice in ["high", "medium", "low"] {
        try db.execute(sql: "UPDATE podcast SET quietAudioProtection = ?", arguments: [choice])
        #expect(try String.fetchOne(db, sql: "SELECT quietAudioProtection FROM podcast") == choice)
      }
      #expect(throws: DatabaseError.self) {
        try db.execute(sql: "UPDATE podcast SET quietAudioProtection = 'custom'")
      }
      try db.execute(sql: "UPDATE podcast SET quietAudioProtection = NULL")
      #expect(try String.fetchOne(db, sql: "SELECT quietAudioProtection FROM podcast") == nil)
    }
    #expect(Container.shared.standardDefaults().string(forKey: "quietAudioProtection") == nil)
  }
}
