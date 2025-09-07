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

    let cachedURL = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(cachedURL)

    let actualData = try await CacheHelpers.cachedFileData(for: cachedURL)
    #expect(actualData == data)
  }

  @Test("episode removed from queue gets cache cleared")
  func episodeRemovedFromQueueGetsCacheCleared() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    try await CacheHelpers.simulateBackgroundFinish(taskID)

    let cachedURL = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(cachedURL)

    try await queue.dequeue(podcastEpisode.id)
    try await CacheHelpers.waitForNotCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFileRemoved(cachedURL)
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

  @Test("second episode removed from queue gets cache cleared")
  func secondEpisodeRemovedFromQueueGetsCacheCleared() async throws {
    let (podcastEpisode1, podcastEpisode2) = try await Create.twoPodcastEpisodes()

    let initialTaskID = try await CacheHelpers.unshiftToQueue(podcastEpisode1.id)
    try await CacheHelpers.simulateBackgroundFinish(initialTaskID)

    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode2.id)

    try await CacheHelpers.simulateBackgroundFinish(taskID)

    let cachedURL = try await CacheHelpers.waitForCached(podcastEpisode2.id)
    try await CacheHelpers.waitForCachedFile(cachedURL)

    try await queue.dequeue(podcastEpisode2.id)
    try await CacheHelpers.waitForNotCached(podcastEpisode2.id)
    try await CacheHelpers.waitForCachedFileRemoved(cachedURL)
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

    var cachedURL = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(cachedURL)

    try await queue.dequeue(podcastEpisode.id)
    try await CacheHelpers.waitForNotCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFileRemoved(cachedURL)

    taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)
    try await CacheHelpers.simulateBackgroundFinish(taskID)

    cachedURL = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(cachedURL)
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

  // MARK: - Delegate

  @Test("completion callback moves file immediately")
  func completionCallbackMovesFileImmediately() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    let fileURL = try await CacheHelpers.simulateBackgroundFinish(taskID)
    #expect(!fileManager.fileExists(at: fileURL))
  }

  @Test("download finishing for a deleted episode is cleaned up")
  func downloadFinishingForADeletedEpisodeIsCleanedUp() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.downloadToCache(podcastEpisode.id)

    try await repo.delete(podcastEpisode.podcast.id)

    let fileURL = try await CacheHelpers.simulateBackgroundFinish(taskID)
    try await CacheHelpers.waitForFileRemoved(fileURL)
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
    try await CacheHelpers.downloadToCache(podcastEpisode.id)

    try await cacheManager.clearCache(for: podcastEpisode.id)
    try await CacheHelpers.waitForNoDownloadTaskID(podcastEpisode.id)
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

  @Test("clearCache does nothing if episode is queued")
  func clearCacheDoesNothingIfEpisodeIsQueued() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    #expect(try await cacheManager.clearCache(for: podcastEpisode.id) == nil)
    try await CacheHelpers.waitForDownloadTaskID(podcastEpisode.id)
  }

  @Test("clearing cache of an uncached episode does nothing")
  func clearingCacheOfAnUncachedEpisodeDoesNothing() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    #expect(try await cacheManager.clearCache(for: podcastEpisode.id) == nil)
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
}
