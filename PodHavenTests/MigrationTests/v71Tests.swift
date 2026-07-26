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

  private func defaults() throws -> FakeKeyValueStore {
    try #require(Container.shared.standardDefaults() as? FakeKeyValueStore)
  }

  @Test("v71 removes obsolete keys and normalizes legacy strings")
  func removesAndNormalizes() throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v70")
    let defaults = try defaults()
    defaults.set(Data("{}".utf8), forKey: "navigationEpisodesTopDestination")
    defaults.set(Data("{}".utf8), forKey: "navigationPodcastsTopDestination")
    defaults.set("System", forKey: "appearanceMode")
    defaults.set("Next Chapter", forKey: "nextTrackBehavior")
    defaults.set("grid", forKey: "PodcastsList-displayMode")
    defaults.set("byTitle", forKey: "PodcastsList-sortMethod-Subscriptions")
    defaults.set("invalid", forKey: "PodcastsList-sortMethod-Broken")

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v71")

    #expect(defaults.data(forKey: "navigationEpisodesTopDestination") == nil)
    #expect(defaults.data(forKey: "navigationPodcastsTopDestination") == nil)
    #expect(String.load(from: defaults, forKey: "appearanceMode") == "System")
    #expect(String.load(from: defaults, forKey: "nextTrackBehavior") == "Next Chapter")
    #expect(String.load(from: defaults, forKey: "PodcastsList-displayMode") == "grid")
    #expect(
      String.load(from: defaults, forKey: "PodcastsList-sortMethod-Subscriptions")
        == "byTitle"
    )
    #expect(defaults.string(forKey: "PodcastsList-sortMethod-Broken") == nil)
    #expect(defaults.data(forKey: "PodcastsList-sortMethod-Broken") == nil)
  }

  @Test("v71 preserves values already stored as JSON Data")
  func preservesJSONData() throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v70")
    let defaults = try defaults()
    let data = try JSONEncoder().encode("Dark")
    defaults.set(data, forKey: "appearanceMode")

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v71")

    #expect(defaults.data(forKey: "appearanceMode") == data)
  }
}
