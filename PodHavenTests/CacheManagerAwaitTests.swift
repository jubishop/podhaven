// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of CacheManager await-download API", .container)
struct CacheManagerAwaitTests {
  @DynamicInjected(\.cacheManager) private var cacheManager

  init() {
    cacheManager.start()
  }

  @Test("cachedURL(downloadingIfNeeded:) returns immediately for an already-cached episode")
  func returnsImmediatelyWhenCached() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.downloadToCache(podcastEpisode.id)
    try await CacheHelpers.simulateBackgroundFinish(taskID)
    let expected = try await CacheHelpers.waitForCached(podcastEpisode.id)

    let result = try await cacheManager.cachedURL(downloadingIfNeeded: podcastEpisode.id)
    #expect(result == expected)
  }

  @Test("cachedURL(downloadingIfNeeded:) starts a download and resolves when it completes")
  func startsDownloadAndResolvesOnCompletion() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    // Start awaiting before the download exists so the latch is registered
    // before the completion callback fires.
    async let pending = cacheManager.cachedURL(downloadingIfNeeded: podcastEpisode.id)

    let taskID = try await CacheHelpers.waitForDownloadTask(podcastEpisode.id)
    try await CacheHelpers.waitForResumed(taskID)
    let data = Data.random()
    try await CacheHelpers.simulateBackgroundFinish(taskID, data: data)

    let resolved = try await pending
    let cachedURL = try #require(resolved)
    let actualData = try await CacheHelpers.cachedFileData(for: cachedURL)
    #expect(actualData == data)
  }

  @Test("cachedURL(downloadingIfNeeded:) resolves nil when the download fails")
  func resolvesNilOnFailure() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    async let pending = cacheManager.cachedURL(downloadingIfNeeded: podcastEpisode.id)

    let taskID = try await CacheHelpers.waitForDownloadTask(podcastEpisode.id)
    try await CacheHelpers.waitForResumed(taskID)
    try await CacheHelpers.simulateBackgroundFailure(taskID)

    let result = try await pending
    #expect(result == nil)
  }

  @Test("a cancelled awaiter does not strand a concurrent awaiter of the same episode")
  func cancelledAwaiterDoesNotStrandConcurrentAwaiter() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let episodeID = podcastEpisode.id
    let cacheManager = self.cacheManager
    let secondResolved = ThreadSafe<CachedURL?>(nil)

    // First awaiter starts the download and parks on the per-episode latch.
    let first = Task { try await cacheManager.cachedURL(downloadingIfNeeded: episodeID) }
    let taskID = try await CacheHelpers.waitForDownloadTask(episodeID)
    try await CacheHelpers.waitForResumed(taskID)
    try await CacheHelpers.waitForDownloading(episodeID)

    // Second awaiter joins while the download is in flight, so it shares the
    // same latch and parks too.
    let second = Task {
      let url = try await cacheManager.cachedURL(downloadingIfNeeded: episodeID)
      secondResolved(url)
    }
    for _ in 0..<50 { await Task.yield() }

    // Cancelling the first awaiter must not remove the shared latch out from
    // under the second; the completion signal must still resolve the second.
    first.cancel()
    try await CacheHelpers.simulateBackgroundFinish(taskID)

    let resolved = try await Wait.forValue { secondResolved() }
    let expected = try await CacheHelpers.waitForCached(episodeID)
    #expect(resolved == expected)

    await #expect(throws: CancellationError.self) {
      _ = try await first.value
    }
    _ = try await second.value
  }

  @Test("cachedURL(downloadingIfNeeded:) starts a fresh download after an earlier attempt failed")
  func recoversWithFreshDownloadAfterFailure() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    // First attempt fails and resolves nil; its latch is opened and removed.
    async let firstPending = cacheManager.cachedURL(downloadingIfNeeded: podcastEpisode.id)
    let failedTaskID = try await CacheHelpers.waitForDownloadTask(podcastEpisode.id)
    try await CacheHelpers.waitForResumed(failedTaskID)
    try await CacheHelpers.simulateBackgroundFailure(failedTaskID)
    let firstResult = try await firstPending
    #expect(firstResult == nil)

    // A later call must start a brand-new download — the failed attempt's latch
    // is gone, so it can't resolve this one early — and resolve to its file.
    async let secondPending = cacheManager.cachedURL(downloadingIfNeeded: podcastEpisode.id)
    let okTaskID = try await CacheHelpers.waitForDownloadTask(podcastEpisode.id)
    try await CacheHelpers.waitForResumed(okTaskID)
    let data = Data.random()
    try await CacheHelpers.simulateBackgroundFinish(okTaskID, data: data)

    let resolved = try #require(try await secondPending)
    let actualData = try await CacheHelpers.cachedFileData(for: resolved)
    #expect(actualData == data)
  }
}
