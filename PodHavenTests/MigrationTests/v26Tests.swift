// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("v26 migration tests", .container, .serialized)
class V26MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)

  private let oldKey = "PlayManager-currentEpisodeID"
  private let newKey = "currentEpisodeID"

  @Test("v26 migration moves currentEpisodeID from PlayManager to SharedState key")
  func testV26Migration() async throws {
    // Clean up UserDefaults before test
    UserDefaults.standard.removeObject(forKey: oldKey)
    UserDefaults.standard.removeObject(forKey: newKey)

    let migrator = try Schema.makeMigrator()

    // Apply migrations up to v25
    try migrator.migrate(appDB.db, upTo: "v25")

    let testEpisodeID = 42

    // Set the old key value
    UserDefaults.standard.set(testEpisodeID, forKey: oldKey)
    #expect(UserDefaults.standard.integer(forKey: oldKey) == testEpisodeID)
    #expect(UserDefaults.standard.object(forKey: newKey) == nil)

    // Apply v26 migration
    try migrator.migrate(appDB.db, upTo: "v26")

    // Verify old key is removed and new key has the value
    #expect(UserDefaults.standard.object(forKey: oldKey) == nil)
    #expect(UserDefaults.standard.integer(forKey: newKey) == testEpisodeID)
  }

  @Test("v26 migration does nothing if old key doesn't exist")
  func testV26MigrationNoOldKey() async throws {
    // Clean up UserDefaults before test
    UserDefaults.standard.removeObject(forKey: oldKey)
    UserDefaults.standard.removeObject(forKey: newKey)

    let migrator = try Schema.makeMigrator()

    // Apply migrations up to v25
    try migrator.migrate(appDB.db, upTo: "v25")

    // Apply v26 migration
    try migrator.migrate(appDB.db, upTo: "v26")

    // Verify nothing was set
    #expect(UserDefaults.standard.object(forKey: oldKey) == nil)
    #expect(UserDefaults.standard.object(forKey: newKey) == nil)
  }
}
