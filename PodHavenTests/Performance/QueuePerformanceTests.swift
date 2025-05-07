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
    let episodeIDs = Array(try await fillQueue(10000).prefix(5000))

    let startTime = Date()
    try await queue.dequeue(episodeIDs)
    let endTime = Date()

    let duration = endTime.timeIntervalSince(startTime)
    #expect(duration < 0.5, "Dequeuing episodes took too long")

    let count = try await fetchQueueCount()
    #expect(count == 5000)
  }

  @Test("performance of appending episodes")
  func testAppendPerformance() async throws {
    let queuedEpisodeIDs = try await fillQueue(1000)
    let unqueuedEpisodeIDs = try await makeEpisodes(1000)

    let episodeIDs = (queuedEpisodeIDs + unqueuedEpisodeIDs).shuffled()

    let startTime = Date()
    try await queue.append(episodeIDs)
    let endTime = Date()

    let duration = endTime.timeIntervalSince(startTime)
    Log.info("Appending episodes took \(duration) seconds")
    // #expect(duration < 0.1)

    let count = try await fetchQueueCount()
    #expect(count == 2000)
  }

  // MARK: - Helpers

  private func makeEpisodes(_ numberOfEpisodes: Int) async throws -> [Episode.ID] {
    let unsavedPodcast = try TestHelpers.unsavedPodcast()
    var unsavedEpisodes: [UnsavedEpisode] = Array(capacity: numberOfEpisodes)
    for _ in 0..<numberOfEpisodes {
      unsavedEpisodes.append(
        try TestHelpers.unsavedEpisode()
      )
    }

    let series = try await repo.insertSeries(unsavedPodcast, unsavedEpisodes: unsavedEpisodes)
    return series.episodes.map(\.id)
  }

  private func fillQueue(_ numberOfEpisodes: Int) async throws -> [Episode.ID] {
    let unsavedPodcast = try TestHelpers.unsavedPodcast()
    var unsavedEpisodes: [UnsavedEpisode] = Array(capacity: numberOfEpisodes)
    for index in 0..<numberOfEpisodes {
      unsavedEpisodes.append(
        try TestHelpers.unsavedEpisode(queueOrder: index)
      )
    }

    let series = try await repo.insertSeries(unsavedPodcast, unsavedEpisodes: unsavedEpisodes)

    let count = try await fetchQueueCount()
    #expect(count == numberOfEpisodes)

    return series.episodes.map(\.id).shuffled()
  }

  private func fetchQueueCount() async throws -> Int {
    try await repo.db.read { db in
      try Episode
        .filter(Column("queueOrder") != nil)
        .fetchCount(db)
    }
  }
}
