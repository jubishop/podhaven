// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of CacheManager tests", .container)
@MainActor class CacheManagerTests {
  @DynamicInjected(\.cacheBackgroundDelegate) private var cacheBackgroundDelegate
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.stateManager) private var stateManager

  private var fileManager: FakeFileManager {
    Container.shared.fileManager() as! FakeFileManager
  }
  private var session: FakeDataFetchable {
    Container.shared.cacheManagerSession() as! FakeDataFetchable
  }
  private var sharedState: SharedState {
    Container.shared.sharedState()
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
  }

  // MARK: - Queue Observation Tests

  @Test("episode added to queue gets cached")
  func episodeAddedToQueueGetsCached() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    let data = Data.random()
    let fileURL = try await CacheHelpers.simulateBackgroundFinish(taskID, data: data)
    try await CacheHelpers.waitForNotDownloading(podcastEpisode.id)
    try await CacheHelpers.waitForFileRemoved(fileURL)

    let cachedURL = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(cachedURL)

    let actualData = try await CacheHelpers.cachedFileData(for: cachedURL)
    #expect(actualData == data)
  }

  @Test("second episode added to queue gets cached")
  func secondEpisodeAddedToQueueGetsCached() async throws {
    let (podcastEpisode1, podcastEpisode2) = try await Create.twoPodcastEpisodes()

    let initialTaskID = try await CacheHelpers.unshiftToQueue(podcastEpisode1.id)
    try await CacheHelpers.simulateBackgroundFinish(initialTaskID)

    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode2.id)

    let data = Data.random()
    let fileURL = try await CacheHelpers.simulateBackgroundFinish(taskID, data: data)
    try await CacheHelpers.waitForFileRemoved(fileURL)

    let cachedURL = try await CacheHelpers.waitForCached(podcastEpisode2.id)
    try await CacheHelpers.waitForCachedFile(cachedURL)

    let actualData = try await CacheHelpers.cachedFileData(for: cachedURL)
    #expect(actualData == data)
  }

  @Test("download failure clears cache for episode")
  func downloadFailureClearsCacheForEpisode() async throws {

    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    try await CacheHelpers.simulateBackgroundFailure(taskID)

    try await CacheHelpers.waitForNotDownloading(podcastEpisode.id)
    try await CacheHelpers.waitForNotCached(podcastEpisode.id)
  }

  @Test("multiple concurrent queued episodes are cached successfully")
  func multipleConcurrentQueuedEpisodesAreCachedSuccessfully() async throws {
    let (podcastEpisode1, podcastEpisode2) = try await Create.twoPodcastEpisodes()

    let taskID1 = try await CacheHelpers.unshiftToQueue(podcastEpisode1.id)
    let taskID2 = try await CacheHelpers.unshiftToQueue(podcastEpisode2.id)

    let data1 = Data.random()
    let fileURL1 = try await CacheHelpers.simulateBackgroundFinish(taskID1, data: data1)
    try await CacheHelpers.waitForFileRemoved(fileURL1)

    let data2 = Data.random()
    let fileURL2 = try await CacheHelpers.simulateBackgroundFinish(taskID2, data: data2)
    try await CacheHelpers.waitForFileRemoved(fileURL2)

    let cachedURL1 = try await CacheHelpers.waitForCached(podcastEpisode1.id)
    let cachedURL2 = try await CacheHelpers.waitForCached(podcastEpisode2.id)

    let actualData1 = try await CacheHelpers.cachedFileData(for: cachedURL1)
    let actualData2 = try await CacheHelpers.cachedFileData(for: cachedURL2)

    #expect(actualData1 == data1)
    #expect(actualData2 == data2)
  }

  @Test("caching updates duration from asset loader")
  func cachingUpdatesDurationFromAssetLoader() async throws {
    let expectedDuration = CMTime(seconds: 123, preferredTimescale: 1)
    await episodeAssetLoader.setDefaultHandler { _ in (true, expectedDuration) }

    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    let fileURL = try await CacheHelpers.simulateBackgroundFinish(taskID)
    try await CacheHelpers.waitForFileRemoved(fileURL)

    let cachedURL = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(cachedURL)

    let updatedEpisode: Episode = try await repo.episode(podcastEpisode.id)!
    #expect(updatedEpisode.duration == expectedDuration)

    await episodeAssetLoader.setDefaultHandler { _ in
      (true, CMTime.seconds(Double.random(in: 1...999)))
    }
  }

  @Test("asset loader failure skips caching")
  func assetLoaderFailureSkipsCaching() async throws {
    enum LoaderFailure: Error { case failure }
    await episodeAssetLoader.setDefaultHandler { _ in throw LoaderFailure.failure }

    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    _ = try await CacheHelpers.simulateBackgroundFinish(taskID)
    try await CacheHelpers.waitForNotCached(podcastEpisode.id)

    let episode: Episode = try await repo.episode(podcastEpisode.id)!
    #expect(episode.cacheStatus == .uncached)
    #expect(episode.cachedURL == nil)
    #expect(episode.duration == .zero)
  }

  // MARK: - Delegate

  @Test("completion callback moves file immediately")
  func completionCallbackMovesFileImmediately() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    let fileURL = try await CacheHelpers.simulateBackgroundFinish(taskID)
    #expect(!fileManager.fileExists(at: fileURL))
  }

  // downloading is cleared only after the cached filename is written, so a
  // request arriving mid-completion sees .caching and no-ops, not a duplicate.
  @Test("a request arriving mid-completion does not start a duplicate download")
  func requestMidCompletionDoesNotRestartDownload() async throws {
    let assetStarted = AsyncSemaphore(value: 0)
    let assetRelease = AsyncSemaphore(value: 0)
    await episodeAssetLoader.setDefaultHandler { _ in
      assetStarted.signal()
      try await assetRelease.waitUnlessCancelled()
      return (true, CMTime.seconds(30))
    }

    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.downloadToCache(podcastEpisode.id)

    // Drive completion concurrently; it parks in the gated asset load, before
    // the filename is written and flag cleared.
    let finish = Task { try await CacheHelpers.simulateBackgroundFinish(taskID) }
    await assetStarted.wait()

    let duplicate = try await cacheManager.downloadToCache(for: podcastEpisode.id)
    #expect(duplicate == nil)

    assetRelease.signal()
    _ = try await finish.value
    try await CacheHelpers.waitForCached(podcastEpisode.id)
  }

  @Test("download finishing for a deleted episode is cleaned up")
  func downloadFinishingForADeletedEpisodeIsCleanedUp() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.downloadToCache(podcastEpisode.id)

    try await repo.deletePodcast(podcastEpisode.podcast.id)

    let fileURL = try await CacheHelpers.simulateBackgroundFinish(taskID)
    try await CacheHelpers.waitForFileRemoved(fileURL)
  }

  // MARK: - Progress Tracking

  @Test("progress updates cache state and clears on finish")
  func progressUpdatesCacheStateAndClearsOnFinish() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    await session.progressDownload(
      taskID: taskID,
      totalBytesWritten: 50,
      totalBytesExpectedToWrite: 100
    )
    try await CacheHelpers.waitForProgress(podcastEpisode.id, progress: 0.5)

    try await CacheHelpers.simulateBackgroundFinish(taskID)
    try await CacheHelpers.waitForProgress(podcastEpisode.id, progress: nil)
  }

  @Test("progress clears on completion error")
  func progressClearsOnCompletionError() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    await session.progressDownload(
      taskID: taskID,
      totalBytesWritten: 50,
      totalBytesExpectedToWrite: 100
    )
    try await CacheHelpers.waitForProgress(podcastEpisode.id, progress: 0.5)

    try await CacheHelpers.simulateBackgroundFailure(taskID)
    try await CacheHelpers.waitForProgress(podcastEpisode.id, progress: nil)
  }

  // MARK: - OnDeck Observation

  @Test("episode set as onDeck gets cached")
  func episodeSetAsOnDeckGetsCached() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.load(podcastEpisode)

    try await CacheHelpers.waitForDownloading(podcastEpisode.id)
    let taskID = try await CacheHelpers.waitForDownloadTask(podcastEpisode.id)
    try await CacheHelpers.waitForResumed(taskID)

    let data = Data.random()
    let fileURL = try await CacheHelpers.simulateBackgroundFinish(taskID, data: data)
    try await CacheHelpers.waitForFileRemoved(fileURL)

    let cachedURL = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(cachedURL)

    let actualData = try await CacheHelpers.cachedFileData(for: cachedURL)
    #expect(actualData == data)
  }

  // MARK: - OnDeck

  @Test("dequeue while onDeck does not clear cache")
  func dequeueWhileOnDeckDoesNotClearCache() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)
    try await CacheHelpers.simulateBackgroundFinish(taskID)
    try await CacheHelpers.waitForCached(podcastEpisode.id)

    try await PlayHelpers.load(podcastEpisode)
    try await queue.dequeue(podcastEpisode.id)
    try await PlayHelpers.waitForQueue([])

    try await CacheHelpers.waitForCached(podcastEpisode.id)
  }

  @Test("clearCache does nothing if episode is currentEpisodeID")
  func clearCacheDoesNothingIfEpisodeIsCurrentEpisodeID() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)
    try await CacheHelpers.simulateBackgroundFinish(taskID)
    try await CacheHelpers.waitForCached(podcastEpisode.id)

    try await PlayHelpers.load(podcastEpisode)

    #expect(try await cacheManager.clearCache(for: podcastEpisode.id) == nil)
    try await CacheHelpers.waitForCached(podcastEpisode.id)
  }

  // MARK: - downloadToCache

  @Test("downloadToCache begins download")
  func downloadToCacheBeginsDownload() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await cacheManager.downloadToCache(for: podcastEpisode.id)!
    try await CacheHelpers.waitForResumed(taskID)
    try await CacheHelpers.waitForDownloading(podcastEpisode.id)
  }

  @Test("downloadToCache does nothing if already caching")
  func downloadToCacheDoesNothingIfAlreadyCaching() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    try await CacheHelpers.downloadToCache(podcastEpisode.id)

    #expect(try await cacheManager.downloadToCache(for: podcastEpisode.id) == nil)
  }

  @Test("downloadToCache does nothing if already cached")
  func downloadToCacheDoesNothingIfAlreadyCached() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.downloadToCache(podcastEpisode.id)
    try await CacheHelpers.simulateBackgroundFinish(taskID)
    try await CacheHelpers.waitForCached(podcastEpisode.id)

    #expect(try await cacheManager.downloadToCache(for: podcastEpisode.id) == nil)
  }

  @Test("concurrent same-episode downloads create one task")
  func concurrentSameEpisodeDownloadsCreateOneTask() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let fakeRepo = try #require(repo as? FakeRepo)
    await fakeRepo.barrierNextPodcastEpisodeFetches(count: 2)

    async let firstTaskID = cacheManager.downloadToCache(for: podcastEpisode.id)
    async let secondTaskID = cacheManager.downloadToCache(for: podcastEpisode.id)
    let results = try await (firstTaskID, secondTaskID)
    let startedTaskIDs = [results.0, results.1].compactMap { $0 }

    let createdTaskCount = await session.allCreatedTasks.count
    #expect(startedTaskIDs.count == 1)
    #expect(createdTaskCount == 1)
    try await CacheHelpers.waitForResumed(try #require(startedTaskIDs.first))
  }

  @Test("clearCache cancels a download between its claim and task creation")
  func clearCacheCancelsDownloadWhileClaimIsStarting() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let fakeRepo = try #require(repo as? FakeRepo)
    let gate = await fakeRepo.gateNextWinningDownloadClaim()
    defer { gate.release.open() }

    let download = Task {
      try await cacheManager.downloadToCache(for: podcastEpisode.id)
    }
    try await gate.claimed.wait()

    let clear = Task {
      try await cacheManager.clearCache(for: podcastEpisode.id)
    }
    try await CacheHelpers.waitForNotDownloading(podcastEpisode.id)
    gate.release.open()

    #expect(try await clear.value == nil)
    let taskID = try await download.value
    let createdTasks = await session.allCreatedTasks
    let episode = try #require(try await repo.episode(podcastEpisode.id))
    #expect(taskID == nil)
    #expect(createdTasks.isEmpty)
    #expect(!episode.downloading)
  }

  @Test("download after clearCache does not inherit a prior start's cancellation")
  func downloadAfterClearCacheUsesFreshStartState() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let fakeRepo = try #require(repo as? FakeRepo)
    let gate = await fakeRepo.gateNextWinningDownloadClaim()
    defer { gate.release.open() }
    fakeRepo.pendingDownloadingFalseSuspend(true)

    let originalDownload = Task {
      try await cacheManager.downloadToCache(for: podcastEpisode.id)
    }
    try await gate.claimed.wait()

    let clearFinished = AsyncLatch<Void>()
    let clear = Task {
      defer { clearFinished.open() }
      return try await cacheManager.clearCache(for: podcastEpisode.id)
    }
    try await fakeRepo.waitForDownloadingFalseSuspended()
    await fakeRepo.resumeAllDownloadingFalseSuspensions()
    await Task.yield()

    #expect(!clearFinished.isOpen)
    gate.release.open()
    #expect(try await originalDownload.value == nil)
    #expect(try await clear.value == nil)

    let replacementTaskID = try await cacheManager.downloadToCache(for: podcastEpisode.id)
    let requiredReplacementTaskID = try #require(replacementTaskID)
    try await CacheHelpers.waitForResumed(requiredReplacementTaskID)
    let current = try #require(try await repo.episode(podcastEpisode.id))
    #expect(current.downloading)
  }

  @Test("multiple concurrent downloads are cached successfully")
  func multipleConcurrentDownloadsAreCachedSuccessfully() async throws {
    let (podcastEpisode1, podcastEpisode2) = try await Create.twoPodcastEpisodes()

    let taskID1 = try await CacheHelpers.downloadToCache(podcastEpisode1.id)
    let taskID2 = try await CacheHelpers.downloadToCache(podcastEpisode2.id)

    let data1 = Data.random()
    let fileURL1 = try await CacheHelpers.simulateBackgroundFinish(taskID1, data: data1)
    try await CacheHelpers.waitForFileRemoved(fileURL1)

    let data2 = Data.random()
    let fileURL2 = try await CacheHelpers.simulateBackgroundFinish(taskID2, data: data2)
    try await CacheHelpers.waitForFileRemoved(fileURL2)

    let cachedURL1 = try await CacheHelpers.waitForCached(podcastEpisode1.id)
    let cachedURL2 = try await CacheHelpers.waitForCached(podcastEpisode2.id)

    let actualData1 = try await CacheHelpers.cachedFileData(for: cachedURL1)
    let actualData2 = try await CacheHelpers.cachedFileData(for: cachedURL2)

    #expect(actualData1 == data1)
    #expect(actualData2 == data2)
  }

  // MARK: - clearCache

  @Test("clearCache stops in progress download")
  func clearCacheStopsInProgressDownload() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.downloadToCache(podcastEpisode.id)

    let clear = Task {
      try await cacheManager.clearCache(for: podcastEpisode.id)
    }
    try await CacheHelpers.waitForCancelled(taskID)
    try await CacheHelpers.simulateBackgroundFailure(taskID)

    _ = try await clear.value
    try await CacheHelpers.waitForNotDownloading(podcastEpisode.id)
  }

  @Test("clearCache clears cached file")
  func clearCacheClearsCachedFile() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.downloadToCache(podcastEpisode.id)

    try await CacheHelpers.simulateBackgroundFinish(taskID)
    let cachedURL = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(cachedURL)

    try await cacheManager.clearCache(for: podcastEpisode.id)
    try await CacheHelpers.waitForNotCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFileRemoved(cachedURL)
  }

  @Test("clearCache wins when an in-progress download completes after its initial read")
  func clearCacheWinsAgainstConcurrentCompletion() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.downloadToCache(podcastEpisode.id)
    let fakeRepo = try #require(repo as? FakeRepo)
    fakeRepo.pendingEpisodeFetchSuspend(true)
    defer { Task { await fakeRepo.resumeAllEpisodeFetchSuspensions() } }

    let clear = Task {
      try await cacheManager.clearCache(for: podcastEpisode.id)
    }
    try await fakeRepo.waitForEpisodeFetchSuspended(count: 1)
    try await CacheHelpers.simulateBackgroundFinish(taskID)
    let completedURL = try await CacheHelpers.waitForCached(podcastEpisode.id)

    await fakeRepo.resumeAllEpisodeFetchSuspensions()
    _ = try await clear.value

    let current = try #require(try await repo.episode(podcastEpisode.id))
    #expect(current.cachedURL == nil)
    #expect(!fileManager.fileExists(at: completedURL.rawValue))
  }

  @Test("clearCache waits for terminal success before applying its final clear")
  func clearCacheWaitsForConcurrentCompletion() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.downloadToCache(podcastEpisode.id)
    let fakeRepo = try #require(repo as? FakeRepo)
    fakeRepo.pendingEpisodeFetchSuspend(true)
    defer { Task { await fakeRepo.resumeAllEpisodeFetchSuspensions() } }

    let finish = Task {
      try await CacheHelpers.simulateBackgroundFinish(taskID)
    }
    try await fakeRepo.waitForEpisodeFetchSuspended(count: 1)

    let clear = Task {
      try await cacheManager.clearCache(for: podcastEpisode.id)
    }
    try await CacheHelpers.waitForCancelled(taskID)
    await fakeRepo.resumeAllEpisodeFetchSuspensions()

    _ = try await finish.value
    let clearedURL = try #require(try await clear.value)
    let current = try #require(try await repo.episode(podcastEpisode.id))
    #expect(current.cachedURL == nil)
    #expect(!fileManager.fileExists(at: clearedURL.rawValue))
  }

  @Test("clearCache does nothing if episode is queued")
  func clearCacheDoesNothingIfEpisodeIsQueued() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    #expect(try await cacheManager.clearCache(for: podcastEpisode.id) == nil)
    try await CacheHelpers.waitForDownloading(podcastEpisode.id)
  }

  @Test("clearing cache of an uncached episode does nothing")
  func clearingCacheOfAnUncachedEpisodeDoesNothing() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    #expect(try await cacheManager.clearCache(for: podcastEpisode.id) == nil)
  }

  // MARK: - canClearCache

  @Test("canClearCache returns true for unqueued episode with no current episode")
  func canClearCacheReturnsTrueForUnqueuedEpisodeWithNoCurrentEpisode() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    #expect(CacheManager.canClearCache(podcastEpisode.episode))
  }

  @Test("canClearCache returns false for queued episode")
  func canClearCacheReturnsFalseForQueuedEpisode() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    try await queue.unshift(podcastEpisode.id)

    let episode = try await repo.episode(podcastEpisode.id)!
    #expect(!CacheManager.canClearCache(episode))
  }

  @Test("canClearCache returns true when currentEpisodeID is a different episode")
  func canClearCacheReturnsTrueWhenCurrentEpisodeIDIsDifferent() async throws {
    let (podcastEpisode1, podcastEpisode2) = try await Create.twoPodcastEpisodes()
    sharedState.currentEpisodeID = podcastEpisode1.id

    #expect(CacheManager.canClearCache(podcastEpisode2.episode))
  }

  // MARK: - downloadToCache Edge Cases

  @Test("downloadToCache returns nil for nonexistent episode")
  func downloadToCacheReturnsNilForNonexistentEpisode() async throws {
    let result = try await cacheManager.downloadToCache(for: Episode.ID(rawValue: -999))
    #expect(result == nil)
  }

  // MARK: - clearCache Edge Cases

  @Test("clearCache returns nil for nonexistent episode")
  func clearCacheReturnsNilForNonexistentEpisode() async throws {
    let result = try await cacheManager.clearCache(for: Episode.ID(rawValue: -999))
    #expect(result == nil)
  }

  // MARK: - Queue Observation Deduplication

  @Test("re-queuing the same episode does not trigger a duplicate download")
  func requeueingSameEpisodeDoesNotTriggerDuplicateDownload() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)
    try await CacheHelpers.simulateBackgroundFinish(taskID)
    try await CacheHelpers.waitForCached(podcastEpisode.id)

    // Dequeue and re-queue the same episode
    try await queue.dequeue(podcastEpisode.id)
    try await queue.unshift(podcastEpisode.id)

    // Should not start a new download since it's already cached
    #expect(try await cacheManager.downloadToCache(for: podcastEpisode.id) == nil)
  }

  // MARK: - OnDeck Deduplication

  @Test("changing onDeck to a different episode caches the new episode")
  func changingOnDeckToADifferentEpisodeCachesNewEpisode() async throws {
    let (podcastEpisode1, podcastEpisode2) = try await Create.twoPodcastEpisodes()

    try await PlayHelpers.load(podcastEpisode1)
    try await CacheHelpers.waitForDownloading(podcastEpisode1.id)
    let taskID1 = try await CacheHelpers.waitForDownloadTask(podcastEpisode1.id)
    try await CacheHelpers.waitForResumed(taskID1)

    try await PlayHelpers.load(podcastEpisode2)
    try await CacheHelpers.waitForDownloading(podcastEpisode2.id)
    let taskID2 = try await CacheHelpers.waitForDownloadTask(podcastEpisode2.id)
    try await CacheHelpers.waitForResumed(taskID2)

    #expect(taskID1 != taskID2)
  }

  // MARK: - Filenames

  @Test("cache filenames fall back to mp3 and preserves extension")
  func cacheFilenameFallbackAndPreserve() async throws {
    let noExt = try await Create.podcastEpisode(
      Create.unsavedEpisode(mediaURL: MediaURL(URL(string: "https://a.b/c/d")!))
    )
    let withExt = try await Create.podcastEpisode(
      Create.unsavedEpisode(mediaURL: MediaURL(URL(string: "https://a.b/c/d.wav")!))
    )
    let noExtTaskID = try await cacheManager.downloadToCache(for: noExt.id)!
    let withExtTaskID = try await cacheManager.downloadToCache(for: withExt.id)!

    try await CacheHelpers.simulateBackgroundFinish(noExtTaskID)
    try await CacheHelpers.simulateBackgroundFinish(withExtTaskID)

    let noExtURL = try await CacheHelpers.waitForCached(noExt.id)
    let withExtURL = try await CacheHelpers.waitForCached(withExt.id)

    #expect(noExtURL.pathExtension == "mp3")
    #expect(withExtURL.pathExtension == "wav")
  }

  // MARK: - Cross-Contamination Regression

  // Regression for "AI Daily Brief plays Braid": URLSession taskIdentifiers
  // restart at 1 with each new background session and used to collide with
  // stale values left in the DB from a prior session. Attribution by
  // taskIdentifier therefore could write one episode's downloaded audio
  // into another episode's cached file slot. Attribution must instead use
  // the taskDescription set at task creation, which is stable across
  // sessions.
  @Test("download attribution uses taskDescription, not taskIdentifier")
  func downloadAttributionUsesTaskDescription() async throws {
    let (podcastEpisode1, podcastEpisode2) = try await Create.twoPodcastEpisodes()

    // Synthesize a finished download whose taskID does not match anything
    // the DB knows about, but whose taskDescription pins it to #2.
    let task = FakeURLSessionDownloadTask(
      taskID: URLSessionDownloadTask.ID(42),
      taskDescription: String(podcastEpisode2.id.rawValue),
      originalRequest: URLRequest(url: podcastEpisode2.episode.mediaURL.rawValue)
    )

    let tempFile = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try await fileManager.writeData(Data.random(), to: tempFile)
    await cacheBackgroundDelegate.urlSession(
      session,
      downloadTask: task,
      didFinishDownloadingTo: tempFile
    )

    let updated2 = try await repo.episode(podcastEpisode2.id)!
    #expect(updated2.cacheStatus == .cached)
    let updated1 = try await repo.episode(podcastEpisode1.id)!
    #expect(updated1.cacheStatus != .cached)
  }

  // Defense-in-depth: even if a task somehow ends up attributed to the wrong
  // episode (e.g. a future regression), the URL mismatch must abort the
  // write so corrupt audio never lands in the wrong slot.
  @Test("download with mismatched URL is refused, leaving the episode uncached")
  func mismatchedURLRefused() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    try await repo.updateDownloading(podcastEpisode.id, downloading: true)

    let task = FakeURLSessionDownloadTask(
      taskDescription: String(podcastEpisode.id.rawValue),
      originalRequest: URLRequest(url: URL(string: "https://wrong.example.com/other.mp3")!)
    )

    let tempFile = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try await fileManager.writeData(Data.random(), to: tempFile)
    await cacheBackgroundDelegate.urlSession(
      session,
      downloadTask: task,
      didFinishDownloadingTo: tempFile
    )

    // The give-up path must clear downloading too, not just skip the write;
    // .uncached asserts both (not cached, not downloading).
    let updated = try await repo.episode(podcastEpisode.id)!
    #expect(updated.cacheStatus == .uncached)
  }

  // A terminal callback can fail to read its episode row (transient DB error),
  // not just find it missing. The id is still parseable from taskDescription,
  // so the give-up path must clear downloading and drop the temp file rather
  // than strand the episode as .caching with no live task until next launch.
  @Test("didFinishDownloadingTo clears state when the episode fetch throws")
  func didFinishDownloadingToClearsStateWhenEpisodeFetchThrows() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    try await repo.updateDownloading(podcastEpisode.id, downloading: true)

    let task = FakeURLSessionDownloadTask(
      taskDescription: String(podcastEpisode.id.rawValue),
      originalRequest: URLRequest(url: podcastEpisode.episode.mediaURL.rawValue)
    )
    let tempFile = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try await fileManager.writeData(Data.random(), to: tempFile)

    let fakeRepo = try #require(repo as? FakeRepo)
    fakeRepo.episodeFetchError(InjectedRepoError())

    await cacheBackgroundDelegate.urlSession(
      session,
      downloadTask: task,
      didFinishDownloadingTo: tempFile
    )

    let updated = try await repo.episode(podcastEpisode.id)!
    #expect(updated.cacheStatus == .uncached)
    #expect(!fileManager.fileExists(at: tempFile))
  }

  @Test("didCompleteWithError clears state when the episode fetch throws")
  func didCompleteWithErrorClearsStateWhenEpisodeFetchThrows() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    try await repo.updateDownloading(podcastEpisode.id, downloading: true)

    let task = FakeURLSessionDownloadTask(
      taskDescription: String(podcastEpisode.id.rawValue),
      originalRequest: URLRequest(url: podcastEpisode.episode.mediaURL.rawValue)
    )

    let fakeRepo = try #require(repo as? FakeRepo)
    fakeRepo.episodeFetchError(InjectedRepoError())

    await cacheBackgroundDelegate.urlSession(
      session,
      task: task,
      didCompleteWithError: InjectedRepoError()
    )

    let updated = try await repo.episode(podcastEpisode.id)!
    #expect(updated.cacheStatus == .uncached)
  }
}

private struct InjectedRepoError: Error, Sendable {}
