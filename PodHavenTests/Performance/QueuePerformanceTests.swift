// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Queue performance tests", .serialized)
struct QueuePerformanceTests {
  private let repo: Repo
  private let queue: Queue

  init() async throws {
    let appDB = AppDB.inMemory()
    repo = Repo.initForTest(appDB)
    queue = Queue.initForTest(appDB)
  }

  @Test("performance of dequeuing 2000 episodes")
  func testDequeuePerformance() async throws {
    let unsavedPodcast = try TestHelpers.unsavedPodcast()
    var unsavedEpisodes: [UnsavedEpisode] = []
    for index in 0..<2000 {
      unsavedEpisodes.append(
        try TestHelpers.unsavedEpisode(guid: "perf_\(index)", queueOrder: index)
      )
    }
    let series = try await repo.insertSeries(unsavedPodcast, unsavedEpisodes: unsavedEpisodes)
    let episodeIDs = series.episodes.map(\.id).shuffled()

    #expect((try await fetchOrder()).count == 2000)

    // Measure dequeue performance
    let startTime = Date()
    try await queue.dequeue(episodeIDs)
    let endTime = Date()

    // Calculate and print duration
    let duration = endTime.timeIntervalSince(startTime)
    print("Dequeuing 2000 episodes took \(duration) seconds")

    // Verify queue is empty
    print(try await fetchOrder())
    #expect((try await fetchOrder()).isEmpty)
  }

  // MARK: - Helpers

  private func fetchOrder() async throws -> [Int] {
    let episodes = try await repo.db.read { db in
      try Episode
        .filter(Column("queueOrder") != nil)
        .order(Column("queueOrder").asc)
        .fetchAll(db)
    }
    return episodes.map { $0.queueOrder ?? -1 }
  }
}
