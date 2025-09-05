// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of CacheManager tests", .container)
@MainActor class CacheManagerTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.cacheBackgroundDelegate) private var cacheBackgroundDelegate
  @DynamicInjected(\.cacheState) private var cacheState
  @DynamicInjected(\.playState) private var playState
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  private var fileManager: FakeFileManager {
    Container.shared.podFileManager() as! FakeFileManager
  }
  private var imageFetcher: FakeImageFetcher {
    Container.shared.imageFetcher() as! FakeImageFetcher
  }
  private var session: FakeDataFetchable {
    Container.shared.cacheManagerSession() as! FakeDataFetchable
  }
  private var sleeper: FakeSleeper {
    Container.shared.sleeper() as! FakeSleeper
  }

  init() async throws {
    try await cacheManager.start()
  }

  // MARK: - Queue Observation Tests

  @Test("episode added to queue gets cached")
  func episodeAddedToQueueGetsCached() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    let data = Data.random()
    let fileURL = try await CacheHelpers.simulateBackgroundFinish(taskID, data: data)
    try await CacheHelpers.waitForNoDownloadTaskID(podcastEpisode.id)
    try await CacheHelpers.waitForFileRemoved(fileURL)

    let fileName = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(fileName)

    let actualData = try await CacheHelpers.cachedFileData(for: fileName)
    #expect(actualData == data)
  }

  @Test("episode removed from queue gets cache cleared")
  func episodeRemovedFromQueueGetsCacheCleared() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    try await CacheHelpers.simulateBackgroundFinish(taskID)

    let fileName = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(fileName)

    try await queue.dequeue(podcastEpisode.id)
    try await CacheHelpers.waitForNotCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFileRemoved(fileName)
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

    let fileName = try await CacheHelpers.waitForCached(podcastEpisode2.id)
    try await CacheHelpers.waitForCachedFile(fileName)

    let actualData = try await CacheHelpers.cachedFileData(for: fileName)
    #expect(actualData == data)
  }

  @Test("second episode removed from queue gets cache cleared")
  func secondEpisodeRemovedFromQueueGetsCacheCleared() async throws {
    let (podcastEpisode1, podcastEpisode2) = try await Create.twoPodcastEpisodes()

    let initialTaskID = try await CacheHelpers.unshiftToQueue(podcastEpisode1.id)
    try await CacheHelpers.simulateBackgroundFinish(initialTaskID)

    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode2.id)

    try await CacheHelpers.simulateBackgroundFinish(taskID)

    let fileName = try await CacheHelpers.waitForCached(podcastEpisode2.id)
    try await CacheHelpers.waitForCachedFile(fileName)

    try await queue.dequeue(podcastEpisode2.id)
    try await CacheHelpers.waitForNotCached(podcastEpisode2.id)
    try await CacheHelpers.waitForCachedFileRemoved(fileName)
  }

  @Test("episode dequeued mid-download does not get cached when download completes")
  func episodeDequeuedMidDownloadDoesNotGetCachedWhenDownloadCompletes() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    try await queue.dequeue(podcastEpisode.id)
    try await CacheHelpers.waitForCancelled(taskID)
    try await CacheHelpers.waitForNoDownloadTaskID(podcastEpisode.id)
    try await CacheHelpers.waitForNotCached(podcastEpisode.id)

    let fileURL = try await CacheHelpers.simulateBackgroundFinish(taskID)
    try await CacheHelpers.waitForFileRemoved(fileURL)

    try await CacheHelpers.waitForCancelled(taskID)
    try await CacheHelpers.waitForNoDownloadTaskID(podcastEpisode.id)
    try await CacheHelpers.waitForNotCached(podcastEpisode.id)
  }

  @Test("download failure clears cache for episode")
  func downloadFailureClearsCacheForEpisode() async throws {
    Log.setSystem()
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    try await CacheHelpers.simulateBackgroundFailure(taskID)

    try await CacheHelpers.waitForNoDownloadTaskID(podcastEpisode.id)
    try await CacheHelpers.waitForNotCached(podcastEpisode.id)
  }

  @Test("requeue immediately after dequeue re-caches")
  func requeueAfterDequeueReCaches() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    var taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    try await CacheHelpers.simulateBackgroundFinish(taskID)

    var fileName = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(fileName)

    try await queue.dequeue(podcastEpisode.id)
    try await CacheHelpers.waitForNotCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFileRemoved(fileName)

    taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)
    try await CacheHelpers.simulateBackgroundFinish(taskID)

    fileName = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(fileName)
  }

  // MARK: - Delegate

  @Test("completion callback moves file immediately")
  func completionCallbackMovesFileImmediately() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    let fileURL = try await CacheHelpers.simulateBackgroundFinish(taskID)
    #expect(!fileManager.fileExists(at: fileURL))
  }

  // MARK: - Artwork Prefetching

  @Test("episode artwork is prefetched when episode is cached")
  func episodeArtworkIsPrefetchedWhenEpisodeIsCached() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    try await CacheHelpers.waitForImagePrefetched(podcastEpisode.image)
  }

  @Test("already cached episode added to queue does not prefetch artwork")
  func alreadyCachedDoesNotPrefetchArtwork() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    try await cacheManager.downloadToCache(for: podcastEpisode.id)
    try await CacheHelpers.waitForDownloadTaskID(podcastEpisode.id)

    try await CacheHelpers.waitForImagePrefetched(podcastEpisode.image, fetchCount: 1)

    #expect(try await cacheManager.downloadToCache(for: podcastEpisode.id) == nil)
    try await CacheHelpers.waitForImagePrefetched(podcastEpisode.image, fetchCount: 1)
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

  @Test("progress clears on cancel by dequeue")
  func progressClearsOnCancelByDequeue() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    await session.progressDownload(
      taskID: taskID,
      totalBytesWritten: 50,
      totalBytesExpectedToWrite: 100
    )
    try await CacheHelpers.waitForProgress(podcastEpisode.id, progress: 0.5)

    try await queue.dequeue(podcastEpisode.id)
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

  @Test("clearCache does nothing if episode is onDeck")
  func clearCacheDoesNothingIfEpisodeIsOnDeck() async throws {
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
    try await CacheHelpers.waitForDownloadTaskID(podcastEpisode.id, taskID: taskID)
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

  // MARK: - clearCache

  @Test("clearCache stops in progress download")
  func clearCacheStopsInProgressDownload() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    try await CacheHelpers.downloadToCache(podcastEpisode.id)

    try await cacheManager.clearCache(for: podcastEpisode.id)
    try await CacheHelpers.waitForNoDownloadTaskID(podcastEpisode.id)
  }

  @Test("clearCache clears cached file")
  func clearCacheClearsCachedFile() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.downloadToCache(podcastEpisode.id)

    try await CacheHelpers.simulateBackgroundFinish(taskID)
    let fileName = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(fileName)

    try await cacheManager.clearCache(for: podcastEpisode.id)
    try await CacheHelpers.waitForNotCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFileRemoved(fileName)
  }

  @Test("clearCache does nothing if episode is queued")
  func clearCacheDoesNothingIfEpisodeIsQueued() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    #expect(try await cacheManager.clearCache(for: podcastEpisode.id) == nil)
    try await CacheHelpers.waitForDownloadTaskID(podcastEpisode.id)
  }

  // MARK: - Filenames

  @Test("generateCacheFilename falls back to mp3 and preserves extension")
  func generateCacheFilenameFallbackAndPreserve() async throws {
    let noExt = try await Create.podcastEpisode(
      Create.unsavedEpisode(media: MediaURL(URL(string: "https://a.b/c/d")!))
    )
    let withExt = try await Create.podcastEpisode(
      Create.unsavedEpisode(media: MediaURL(URL(string: "https://a.b/c/d.wav")!))
    )

    let name1 = CacheManager.generateCacheFilename(for: noExt.episode)
    let name2 = CacheManager.generateCacheFilename(for: withExt.episode)
    #expect(name1.hasSuffix(".mp3"))
    #expect(name2.hasSuffix(".wav"))
  }
}
