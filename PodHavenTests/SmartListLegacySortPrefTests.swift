// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of SmartList legacy sort preference cleanup tests", .container)
class SmartListLegacySortPrefTests {
  @DynamicInjected(\.smartListRepo) private var smartListRepo
  @DynamicInjected(\.standardDefaults) private var standardDefaults

  private func seedLegacyKey(_ title: String, _ json: String) {
    standardDefaults.set(Data(json.utf8), forKey: "EpisodesList-sortMethod-\(title)")
  }

  private func legacyKeys() -> [String] {
    standardDefaults.allKeys.filter { $0.hasPrefix("EpisodesList-sortMethod-") }
  }

  @Test("a valid legacy pref is re-copied onto its row by title and the key is removed")
  func validPrefRecopiedAndKeyRemoved() async throws {
    // Force the migration (which seeds the rows) before planting keys, so this
    // exercises the launch cleanup, not the v54 copy.
    let seeded = try await smartListRepo.fetchAll()
    let liked = try #require(seeded.first { $0.title == "Liked" })
    #expect(liked.sortMethod == .newestFirst)
    seedLegacyKey("Liked", "\"recentlyAdded\"")

    await smartListRepo.migrateLegacySortPreferences()

    let updated = try #require(try await smartListRepo.fetchOne(liked.id))
    #expect(updated.sortMethod == .recentlyAdded)
    #expect(legacyKeys().isEmpty)
  }

  @Test("an undecodable legacy pref is discarded without touching the row")
  func garbagePrefDiscarded() async throws {
    let seeded = try await smartListRepo.fetchAll()
    let finished = try #require(seeded.first { $0.title == "Finished" })
    seedLegacyKey("Finished", "not json at all")

    await smartListRepo.migrateLegacySortPreferences()

    let unchanged = try #require(try await smartListRepo.fetchOne(finished.id))
    #expect(unchanged.sortMethod == .newestFirst)
    #expect(legacyKeys().isEmpty)
  }

  @Test("a legacy pref with no matching row is discarded")
  func unmatchedTitleDiscarded() async throws {
    _ = try await smartListRepo.fetchAll()
    seedLegacyKey("No Such List", "\"oldestFirst\"")

    await smartListRepo.migrateLegacySortPreferences()

    #expect(legacyKeys().isEmpty)
  }

  @Test("the cleanup is a no-op when no legacy keys exist")
  func noKeysNoOp() async throws {
    let before = try await smartListRepo.fetchAll()

    await smartListRepo.migrateLegacySortPreferences()

    let after = try await smartListRepo.fetchAll()
    #expect(after.map(\.sortMethod) == before.map(\.sortMethod))
  }
}
