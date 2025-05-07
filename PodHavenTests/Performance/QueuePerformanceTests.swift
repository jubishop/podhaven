// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Queue performance tests", .serialized)
class QueuePerformanceTests {
  private let appDB: AppDB
  private let repo: Repo
  private let queue: Queue

  init() async throws {
    appDB = AppDB.onDisk("queuePerformanceTests.sqlite")
    repo = Repo.initForTest(appDB)
    queue = Queue.initForTest(appDB)
  }

  deinit {
    appDB.tearDown()
  }

  @Test("performance of dequeuing episodes")
  func testDequeuePerformance() async throws {
    let numberOfEpisodes = 2000
    let unsavedPodcast = try TestHelpers.unsavedPodcast()
    var unsavedEpisodes: [UnsavedEpisode] = Array(capacity: numberOfEpisodes)
    for index in 0..<numberOfEpisodes {
      unsavedEpisodes.append(
        try TestHelpers.unsavedEpisode(guid: "perf_\(index)", queueOrder: index)
      )
    }
    let series = try await repo.insertSeries(unsavedPodcast, unsavedEpisodes: unsavedEpisodes)
    let episodeIDs = series.episodes.map(\.id).shuffled()

    #expect((try await fetchOrder()).count == numberOfEpisodes)

    // Measure dequeue performance
    let startTime = Date()
    try await queue.dequeue(episodeIDs)
    let endTime = Date()

    // Calculate and print duration
    let duration = endTime.timeIntervalSince(startTime)
    print("Dequeuing \(numberOfEpisodes) episodes took \(duration) seconds")

    // Verify queue is empty
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
