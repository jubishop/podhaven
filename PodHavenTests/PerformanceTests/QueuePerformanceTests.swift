// Copyright Justin Bishop, 2025

import Factory
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Queue performance tests", .serialized, .container)
class QueuePerformanceTests {
  @LazyInjected(\.queue) private var queue
  @LazyInjected(\.repo) private var repo

  init() async throws {
    Container.shared.appDB
      .context(.test) {
        AppDB.onDisk("queuePerformanceTests.sqlite")
      }
      .scope(.cached)
  }

  deinit {
    Container.shared.appDB().tearDown()
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
    let queuedEpisodeIDs = try await fillQueue(2500)
    let unqueuedEpisodeIDs = try await makeEpisodes(2500)

    let episodeIDs = (queuedEpisodeIDs + unqueuedEpisodeIDs).shuffled()

    let startTime = Date()
    try await queue.append(episodeIDs)
    let endTime = Date()

    let duration = endTime.timeIntervalSince(startTime)
    #expect(duration < 0.5, "Appending episodes took too long")

    let count = try await fetchQueueCount()
    #expect(count == 5000)
  }

  @Test("performance of unshifting episodes")
  func testUnshiftPerformance() async throws {
    let queuedEpisodeIDs = try await fillQueue(2500)
    let unqueuedEpisodeIDs = try await makeEpisodes(2500)

    let episodeIDs = (queuedEpisodeIDs + unqueuedEpisodeIDs).shuffled()

    let startTime = Date()
    try await queue.unshift(episodeIDs)
    let endTime = Date()

    let duration = endTime.timeIntervalSince(startTime)
    #expect(duration < 0.5, "Unsifting episodes took too long")

    let count = try await fetchQueueCount()
    #expect(count == 5000)
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
    return try await repo.db.read { db in
      try Episode
        .filter(Column("queueOrder") != nil)
        .fetchCount(db)
    }
  }
}
