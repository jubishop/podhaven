// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of CacheManager await-download API", .container)
struct CacheManagerAwaitTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.repo) private var repo

  private var fileManager: any FileManaging { Container.shared.fileManager() }
  private var session: FakeDataFetchable {
    Container.shared.cacheManagerSession() as! FakeDataFetchable
  }

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

    // Await before the download exists so the latch registers first.
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

    // Second awaiter joins in-flight, sharing the same latch.
    let second = Task {
      let url = try await cacheManager.cachedURL(downloadingIfNeeded: episodeID)
      secondResolved(url)
    }
    for _ in 0..<50 { await Task.yield() }

    // Cancelling the first must not strand the second on the shared latch.
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

    // A later call starts a fresh download; the failed latch can't resolve it early.
    async let secondPending = cacheManager.cachedURL(downloadingIfNeeded: podcastEpisode.id)
    let okTaskID = try await CacheHelpers.waitForDownloadTask(podcastEpisode.id)
    try await CacheHelpers.waitForResumed(okTaskID)
    let data = Data.random()
    try await CacheHelpers.simulateBackgroundFinish(okTaskID, data: data)

    let resolved = try #require(try await secondPending)
    let actualData = try await CacheHelpers.cachedFileData(for: resolved)
    #expect(actualData == data)
  }

  @Test("a stale callback cannot resolve a replacement download attempt")
  func staleCallbackDoesNotResolveReplacementAttempt() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let episodeID = podcastEpisode.id
    let fakeRepo = try #require(repo as? FakeRepo)

    async let firstPending = cacheManager.cachedURL(downloadingIfNeeded: episodeID)
    let firstTaskID = try await CacheHelpers.waitForDownloadTask(episodeID)
    try await CacheHelpers.waitForResumed(firstTaskID)

    fakeRepo.pendingDownloadingFalseSuspend(true)
    let finishFirst = Task {
      try await CacheHelpers.simulateBackgroundFailure(firstTaskID)
    }
    try await fakeRepo.waitForDownloadingFalseSuspended()

    fakeRepo.pendingEpisodeFetchSuspend(true)
    let replacement = Task {
      try await cacheManager.cachedURL(downloadingIfNeeded: episodeID)
    }
    let description = String(episodeID.rawValue)
    let replacementTaskID = try await Wait.forValue {
      await session.downloadTasks()
        .first {
          $0.taskDescription == description && $0.taskID != firstTaskID
        }?
        .taskID
    }
    try await CacheHelpers.waitForResumed(replacementTaskID)
    try await fakeRepo.waitForEpisodeFetchSuspended(count: 1)

    fakeRepo.pendingEpisodeFetchSuspend(true)
    let cancelledPeer = Task {
      try await cacheManager.cachedURL(downloadingIfNeeded: episodeID)
    }
    try await fakeRepo.waitForEpisodeFetchSuspended(count: 2)

    await fakeRepo.resumeAllDownloadingFalseSuspensions()
    try await finishFirst.value
    #expect(try await firstPending == nil)

    cancelledPeer.cancel()
    await fakeRepo.resumeAllEpisodeFetchSuspensions()
    await #expect(throws: CancellationError.self) {
      _ = try await cancelledPeer.value
    }

    let data = Data.random()
    try await CacheHelpers.simulateBackgroundFinish(replacementTaskID, data: data)

    let resolved = try #require(try await replacement.value)
    let actualData = try await CacheHelpers.cachedFileData(for: resolved)
    #expect(actualData == data)
  }

  @Test("cachedURL(downloadingIfNeeded:) re-downloads when the cached file is missing on disk")
  func redownloadsWhenCachedFileIsMissing() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let staleTaskID = try await CacheHelpers.downloadToCache(podcastEpisode.id)
    try await CacheHelpers.simulateBackgroundFinish(staleTaskID)
    let staleURL = try await CacheHelpers.waitForCached(podcastEpisode.id)

    // A cached row whose file is gone, e.g. a crash between clearCache's file
    // delete and its DB update.
    try fileManager.removeItem(at: staleURL.rawValue)

    async let pending = cacheManager.cachedURL(downloadingIfNeeded: podcastEpisode.id)

    let taskID = try await CacheHelpers.waitForDownloadTask(podcastEpisode.id)
    try await CacheHelpers.waitForResumed(taskID)
    let data = Data.random()
    try await CacheHelpers.simulateBackgroundFinish(taskID, data: data)

    let resolved = try #require(try await pending)
    let actualData = try await CacheHelpers.cachedFileData(for: resolved)
    #expect(actualData == data)
  }

  @Test("cachedURL(downloadingIfNeeded:) awaits a download reattached after relaunch")
  func awaitsReattachedDownloadWithoutLatch() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let episodeID = podcastEpisode.id

    // Mimic a relaunch: a live reattached task with downloading == true but no
    // in-memory latch yet.
    let task = session.createDownloadTask(
      with: URLRequest(url: podcastEpisode.episode.mediaURL.rawValue),
      taskDescription: String(episodeID.rawValue)
    )
    task.resume()
    try await repo.updateDownloading(episodeID, downloading: true)

    // cachedURL must adopt a latch and suspend, not return a premature nil.
    async let pending = cacheManager.cachedURL(downloadingIfNeeded: episodeID)
    for _ in 0..<50 { await Task.yield() }

    let data = Data.random()
    try await CacheHelpers.simulateBackgroundFinish(task.taskID, data: data)

    let resolved = try #require(try await pending)
    let actualData = try await CacheHelpers.cachedFileData(for: resolved)
    #expect(actualData == data)
  }
}
