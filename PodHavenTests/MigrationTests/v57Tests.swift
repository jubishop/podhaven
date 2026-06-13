// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v57 migration tests", .container)
class V57MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  private static let oldKey = "alwaysShowPodcastImageInUpNext"
  private static let newKey = "alwaysShowPodcastImageForUpNextRecommendations"

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  private var defaults: FakeKeyValueStore {
    Container.shared.standardDefaults() as! FakeKeyValueStore
  }

  // MARK: - Helpers

  private func seedBool(_ value: Bool, forKey key: String) throws {
    let data = try JSONEncoder().encode(value)
    defaults.set(data, forKey: key)
  }

  private func loadBool(forKey key: String) throws -> Bool? {
    guard let data = defaults.data(forKey: key) else { return nil }
    return try JSONDecoder().decode(Bool.self, from: data)
  }

  // MARK: - Tests

  @Test("seeds recommendations key from queue key when queue key is true")
  func testSeedsTrue() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v56")
    try seedBool(true, forKey: Self.oldKey)

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v57")

    #expect(try loadBool(forKey: Self.newKey) == true)
    #expect(try loadBool(forKey: Self.oldKey) == true)
  }

  @Test("seeds recommendations key from queue key when queue key is false")
  func testSeedsFalse() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v56")
    try seedBool(false, forKey: Self.oldKey)

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v57")

    #expect(try loadBool(forKey: Self.newKey) == false)
    #expect(try loadBool(forKey: Self.oldKey) == false)
  }

  @Test("does not seed recommendations key when queue key is missing")
  func testNoSeedWhenOldMissing() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v56")

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v57")

    #expect(try loadBool(forKey: Self.newKey) == nil)
  }

  @Test("does not overwrite recommendations key if it is already set")
  func testDoesNotOverwriteExistingNewKey() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v56")
    try seedBool(true, forKey: Self.oldKey)
    try seedBool(false, forKey: Self.newKey)

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v57")

    #expect(try loadBool(forKey: Self.newKey) == false)
  }

  @Test("skips when queue key is corrupt and leaves recommendations key missing")
  func testCorruptOldKey() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v56")
    defaults.set(Data([0xFF, 0xFE]), forKey: Self.oldKey)

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v57")

    #expect(try loadBool(forKey: Self.newKey) == nil)
  }
}
