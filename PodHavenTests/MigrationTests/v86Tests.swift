// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v86 migration tests", .container)
struct V86MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator = Schema.makeMigrator()

  private struct Probe {
    let index: String
    let sql: String
    let arguments: StatementArguments
    let expectedIDs: [Int64]
  }

  // Boolean predicates are bound, as the query interface binds them, so the
  // plans prove SQLite matches a bound value against each index's condition.
  private let probes: [Probe] = [
    Probe(
      index: "episode_downloading_on_id",
      sql: "SELECT id FROM episode WHERE downloading = ?",
      arguments: [true],
      expectedIDs: [861]
    ),
    Probe(
      index: "episode_started_on_pubDate",
      sql: """
        SELECT episode.id FROM episode
        JOIN podcast ON podcast.id = episode.podcastId
        WHERE episode.finishDate IS NULL AND episode.playbackStarted = ?
        ORDER BY episode.pubDate DESC, episode.id ASC
        LIMIT 100
        """,
      arguments: [true],
      expectedIDs: [862]
    ),
    Probe(
      index: "episode_transcribed_on_pubDate",
      sql: """
        SELECT episode.id FROM episode
        JOIN podcast ON podcast.id = episode.podcastId
        WHERE episode.transcript IS NOT NULL
        ORDER BY episode.pubDate DESC, episode.id ASC
        LIMIT 100
        """,
      arguments: [],
      expectedIDs: [863]
    ),
    Probe(
      index: "episode_covered_on_id",
      sql: """
        SELECT id, playbackCoverage FROM episode
        WHERE playbackCoverage IS NOT NULL AND rating IS NULL
        """,
      arguments: [],
      expectedIDs: [864]
    ),
  ]

  @Test("v86 adds partial indexes that serve the episode state queries")
  func addsEpisodeStateIndexes() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v85")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description
          ) VALUES (
            860, 'https://example.com/v86.xml', 'Partial Indexes',
            'https://example.com/v86.jpg', 'Description'
          );
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate,
            downloading, playbackStarted, transcript, playbackCoverage, rating
          ) VALUES
            (
              861, 860, 'v86-1', 'https://example.com/v86-1.mp3', 'Downloading',
              '2026-01-01 00:00:00', 1, 0, NULL, NULL, NULL
            ),
            (
              862, 860, 'v86-2', 'https://example.com/v86-2.mp3', 'Started',
              '2026-01-02 00:00:00', 0, 1, NULL, NULL, NULL
            ),
            (
              863, 860, 'v86-3', 'https://example.com/v86-3.mp3', 'Transcribed',
              '2026-01-03 00:00:00', 0, 0,
              '{"segments":[{"start":0,"end":2,"text":"Indexed words","words":[]}],"locale":"en-US","createdAt":790000000}',
              NULL, NULL
            ),
            (
              864, 860, 'v86-4', 'https://example.com/v86-4.mp3', 'Covered',
              '2026-01-04 00:00:00', 0, 0, NULL, x'01', NULL
            ),
            (
              865, 860, 'v86-5', 'https://example.com/v86-5.mp3', 'Covered And Rated',
              '2026-01-05 00:00:00', 0, 0, NULL, x'01', 'liked'
            ),
            (
              866, 860, 'v86-6', 'https://example.com/v86-6.mp3', 'Plain',
              '2026-01-06 00:00:00', 0, 0, NULL, NULL, NULL
            )
          """
      )
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v86")

    try await appDB.unsafeTestDB.read { [probes] db in
      for probe in probes {
        let condition = try String.fetchOne(
          db,
          sql: "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = ?",
          arguments: [probe.index]
        )
        #expect(condition?.contains("WHERE") == true, "\(probe.index) is partial")

        let plan =
          try Row.fetchAll(
            db,
            sql: "EXPLAIN QUERY PLAN \(probe.sql)",
            arguments: probe.arguments
          )
          .map { $0["detail"] as String }
          .joined(separator: "\n")
        #expect(plan.contains(probe.index), "\(probe.index) serves:\n\(plan)")

        let ids = try Int64.fetchAll(db, sql: probe.sql, arguments: probe.arguments)
        #expect(ids == probe.expectedIDs, "\(probe.index) rows")

        let analyzed = try Bool.fetchOne(
          db,
          sql: "SELECT EXISTS (SELECT 1 FROM sqlite_stat1 WHERE idx = ?)",
          arguments: [probe.index]
        )
        #expect(analyzed == true, "\(probe.index) has planner statistics")
      }
    }
  }
}
