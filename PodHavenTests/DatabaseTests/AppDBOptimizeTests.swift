// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of AppDB optimize", .container)
struct AppDBOptimizeTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.repo) private var repo

  @Test("connections apply the configured analysis_limit")
  func analysisLimitIsBounded() async throws {
    let limit = try await appDB.reader.read { db in
      try Int.fetchOne(db, sql: "PRAGMA analysis_limit") ?? 0
    }
    // A non-default limit proves prepareDatabase ran and bounded optimize's work.
    #expect(limit == 400)
  }

  @Test("optimize refreshes planner stats without throwing")
  func optimizeSucceeds() async throws {
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )

    try await appDB.optimize()

    // The database is still readable after the maintenance write.
    let episodeCount = try await appDB.reader.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episode") ?? 0
    }
    #expect(episodeCount == 1)
  }
}
