// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v33 migration tests", .container)
class V33MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  private var standardDefaults: FakeKeyValueStore {
    Container.shared.standardDefaults() as! FakeKeyValueStore
  }

  private var sharedDefaults: FakeKeyValueStore {
    Container.shared.sharedDefaults() as! FakeKeyValueStore
  }

  // MARK: - Helpers

  private func seedKey(_ key: String, in store: FakeKeyValueStore) throws {
    let data = try JSONEncoder().encode("value")
    store.set(data, forKey: key)
  }

  // MARK: - Standard Defaults Tests

  @Test("preserves active standard defaults keys")
  func testPreservesActiveStandardKeys() async throws {
    try migrator.migrate(appDB.db, upTo: "v32")

    let activeKeys = [
      "shrinkPlayBarOnScroll",
      "cacheSizeLimitGB",
      "defaultPlaybackRate",
      "skipForwardInterval",
      "skipBackwardInterval",
      "enableUndoSeek",
      "maxQueueLength",
      "showNowPlayingInUpNext",
      "alwaysShowPodcastImageInUpNext",
      "showTimeRemainingInEpisodeLists",
      "appearanceMode",
      "nextTrackBehavior",
      "currentEpisodeID",
      "PodcastsList-displayMode",
      "SearchView-displayMode",
    ]
    for key in activeKeys {
      try seedKey(key, in: standardDefaults)
    }

    try migrator.migrate(appDB.db, upTo: "v33")

    for key in activeKeys {
      #expect(standardDefaults.data(forKey: key) != nil, "active key '\(key)' should be preserved")
    }
  }

  @Test("preserves dynamic prefix keys in standard defaults")
  func testPreservesDynamicPrefixKeys() async throws {
    try migrator.migrate(appDB.db, upTo: "v32")

    let prefixedKeys = [
      "PodcastsList-sortMethod-Subscribed",
      "PodcastsList-sortMethod-Unsubscribed",
      "PodcastsList-sortMethod-Untagged",
      "PodcastsList-sortMethod-My Custom Tag",
      "EpisodesList-sortMethod-Recent Episodes",
      "EpisodesList-sortMethod-Cached",
      "EpisodesList-sortMethod-Finished",
    ]
    for key in prefixedKeys {
      try seedKey(key, in: standardDefaults)
    }

    try migrator.migrate(appDB.db, upTo: "v33")

    for key in prefixedKeys {
      #expect(
        standardDefaults.data(forKey: key) != nil,
        "prefixed key '\(key)' should be preserved"
      )
    }
  }

  @Test("removes stale keys from standard defaults")
  func testRemovesStaleStandardKeys() async throws {
    try migrator.migrate(appDB.db, upTo: "v32")

    // Seed one active key to confirm it survives
    try seedKey("maxQueueLength", in: standardDefaults)

    // Seed stale keys
    let staleKeys = [
      "PlayManager-currentEpisodeID",
      "oldSetting",
      "legacyFeatureFlag",
    ]
    for key in staleKeys {
      try seedKey(key, in: standardDefaults)
    }

    try migrator.migrate(appDB.db, upTo: "v33")

    #expect(standardDefaults.data(forKey: "maxQueueLength") != nil)
    for key in staleKeys {
      #expect(standardDefaults.data(forKey: key) == nil, "stale key '\(key)' should be removed")
    }
  }

  // MARK: - Shared Defaults Tests

  @Test("preserves active shared defaults keys")
  func testPreservesActiveSharedKeys() async throws {
    try migrator.migrate(appDB.db, upTo: "v32")

    let activeKeys = [
      "skipForwardInterval",
      "skipBackwardInterval",
      "playbackStatus",
    ]
    for key in activeKeys {
      try seedKey(key, in: sharedDefaults)
    }

    try migrator.migrate(appDB.db, upTo: "v33")

    for key in activeKeys {
      #expect(sharedDefaults.data(forKey: key) != nil, "active key '\(key)' should be preserved")
    }
  }

  @Test("removes stale keys from shared defaults")
  func testRemovesStaleSharedKeys() async throws {
    try migrator.migrate(appDB.db, upTo: "v32")

    try seedKey("playbackStatus", in: sharedDefaults)
    try seedKey("oldWidgetKey", in: sharedDefaults)
    try seedKey("legacySharedState", in: sharedDefaults)

    try migrator.migrate(appDB.db, upTo: "v33")

    #expect(sharedDefaults.data(forKey: "playbackStatus") != nil)
    #expect(sharedDefaults.data(forKey: "oldWidgetKey") == nil)
    #expect(sharedDefaults.data(forKey: "legacySharedState") == nil)
  }

  // MARK: - Edge Cases

  @Test("handles empty stores")
  func testEmptyStores() async throws {
    try migrator.migrate(appDB.db, upTo: "v32")

    #expect(standardDefaults.allKeys.isEmpty)
    #expect(sharedDefaults.allKeys.isEmpty)

    try migrator.migrate(appDB.db, upTo: "v33")

    #expect(standardDefaults.allKeys.isEmpty)
    #expect(sharedDefaults.allKeys.isEmpty)
  }

  @Test("does not remove keys from one store when cleaning the other")
  func testStoreIsolation() async throws {
    try migrator.migrate(appDB.db, upTo: "v32")

    // "staleKey" exists in both stores
    try seedKey("staleKey", in: standardDefaults)
    try seedKey("staleKey", in: sharedDefaults)

    // An active standard key should not protect the same name in shared
    try seedKey("appearanceMode", in: sharedDefaults)

    try migrator.migrate(appDB.db, upTo: "v33")

    // Both stale keys removed from their respective stores
    #expect(standardDefaults.data(forKey: "staleKey") == nil)
    #expect(sharedDefaults.data(forKey: "staleKey") == nil)

    // "appearanceMode" is active in standard but not shared
    #expect(sharedDefaults.data(forKey: "appearanceMode") == nil)
  }

  // MARK: - Direct Static Method Tests

  @Test("cleanupStaleKeys removes only non-matching keys")
  func testCleanupStaleKeysDirect() throws {
    let store = FakeKeyValueStore()
    try seedKey("keep", in: store)
    try seedKey("prefixed-foo", in: store)
    try seedKey("remove-me", in: store)

    Schema.cleanupStaleKeys(
      in: store,
      activeKeys: ["keep"],
      activePrefixes: ["prefixed-"]
    )

    #expect(store.data(forKey: "keep") != nil)
    #expect(store.data(forKey: "prefixed-foo") != nil)
    #expect(store.data(forKey: "remove-me") == nil)
  }

  @Test("cleanupStaleKeys with no prefixes only matches exact keys")
  func testCleanupNoPrefixes() throws {
    let store = FakeKeyValueStore()
    try seedKey("exact", in: store)
    try seedKey("exactWithSuffix", in: store)

    Schema.cleanupStaleKeys(in: store, activeKeys: ["exact"])

    #expect(store.data(forKey: "exact") != nil)
    #expect(store.data(forKey: "exactWithSuffix") == nil)
  }
}
