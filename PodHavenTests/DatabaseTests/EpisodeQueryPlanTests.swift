// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import GRDB
import Testing

@testable import PodHaven

@Suite("of episode state query plans", .container)
struct EpisodeQueryPlanTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.smartListRepo) private var smartListRepo

  @Test("stale download reconciliation reads the downloading index")
  func downloadingEpisodeIDsUsesIndex() async throws {
    let plans = try await queryPlans { _ = try await repo.downloadingEpisodeIDs() }

    #expect(plans.contains { $0.contains("episode_downloading_on_id") }, "\(plans)")
  }

  @Test("the seeded Unfinished list reads the started index")
  func unfinishedListUsesIndex() async throws {
    let lists = try await smartListRepo.fetchAll()
    let unfinished = try #require(lists.first { $0.title == "Unfinished" })

    let plans = try await queryPlans {
      try await firstSmartListPage(unfinished.filter, unfinished.sortMethod)
    }

    #expect(plans.contains { $0.contains("episode_started_on_pubDate") }, "\(plans)")
  }

  @Test("a transcribed Smart List reads the transcribed index")
  func transcribedListUsesIndex() async throws {
    let transcribed = SmartListFilter(conditions: [.state(.isTranscribed)])

    let plans = try await queryPlans { try await firstSmartListPage(transcribed, .newestFirst) }

    #expect(plans.contains { $0.contains("episode_transcribed_on_pubDate") }, "\(plans)")
  }

  @Test("the recommendation rebuild reads the coverage index")
  func scoringContextInputsUsesIndex() async throws {
    let plans = try await queryPlans { _ = try await recommendationRepo.allScoringContextInputs() }

    #expect(plans.contains { $0.contains("episode_covered_on_id") }, "\(plans)")
  }

  // MARK: - Helpers

  private func firstSmartListPage(
    _ filter: SmartListFilter,
    _ sortMethod: SmartListSortMethod
  ) async throws {
    let observation = observatory.listablePodcastEpisodes(
      filter: SmartListFilterEngine.sqlExpression(for: filter) && sortMethod.sqlFilter,
      order: sortMethod.sqlOrdering,
      limit: 100
    )
    for try await _ in observation { break }
  }

  // Traces the test connection while the operation runs, then explains every
  // SELECT it executed, with its bound arguments inlined.
  private func queryPlans(during operation: () async throws -> Void) async throws -> [String] {
    let statements = ThreadSafe<[String]>([])
    try await appDB.unsafeTestDB.write { db in
      db.trace { event in
        guard case .statement(let statement) = event else { return }
        let sql = statement.expandedSQL
        guard sql.hasPrefix("SELECT") else { return }
        statements { $0.append(sql) }
      }
    }

    try await operation()

    return try await appDB.unsafeTestDB.write { db in
      db.trace(options: [])
      return try statements()
        .map { sql in
          try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN \(sql)")
            .map { $0["detail"] as String }
            .joined(separator: "\n")
        }
    }
  }
}
