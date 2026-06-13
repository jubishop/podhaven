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

  @Test("optimize checks tables without connection-local query history")
  func optimizeChecksAllTables() async throws {
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          CREATE TABLE podhaven_optimize_probe(value INTEGER);
          CREATE INDEX podhaven_optimize_probe_value ON podhaven_optimize_probe(value);
          INSERT INTO podhaven_optimize_probe VALUES (1);
          ANALYZE podhaven_optimize_probe;
          WITH RECURSIVE c(x) AS (
            VALUES(2)
            UNION ALL
            SELECT x + 1 FROM c WHERE x < 1000
          )
          INSERT INTO podhaven_optimize_probe SELECT x FROM c;
          """
      )
    }

    let staleStats = try await appDB.reader.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT stat FROM sqlite_stat1 WHERE tbl = 'podhaven_optimize_probe'"
      )
    }
    #expect(staleStats == "1 1")

    try await appDB.optimize()

    let refreshedStats = try await appDB.reader.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT stat FROM sqlite_stat1 WHERE tbl = 'podhaven_optimize_probe'"
      )
    }
    #expect(refreshedStats == "1000 1")
  }
}
