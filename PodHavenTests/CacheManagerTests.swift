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
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

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

  // TODO: Intermittently failing, why?
  @Test("download failure clears cache for episode")
  func downloadFailureClearsCacheForEpisode() async throws {
    Log.setSubsystem()
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    try await CacheHelpers.simulateBackgroundFailure(taskID)

    try await CacheHelpers.waitForNoDownloadTaskID(podcastEpisode.id)
    try await CacheHelpers.waitForNotCached(podcastEpisode.id)
  }

  // MARK: - Artwork Prefetching

  @Test("episode artwork is prefetched when episode is cached")
  func episodeArtworkIsPrefetchedWhenEpisodeIsCached() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    try await CacheHelpers.waitForImagePrefetched(podcastEpisode.image)
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

  //
  //  @Test("background delegate marks failure and clears state")
  //  func backgroundDelegateMarksFailureAndClearsState() async throws {
  //    let podcastEpisode = try await Create.podcastEpisode()
  //
  //    // Mark as queued to simulate a user-initiated download
  //    try await queue.unshift(podcastEpisode.id)
  //
  //    // Wait for scheduling to avoid race with failure path
  //    try await CacheHelpers.waitForCacheStateDownloading(podcastEpisode.id)
  //
  //    // Simulate an error from background session
  //    try await CacheHelpers.simulateBackgroundFailure(
  //      podcastEpisode.id,
  //      error: NSError(domain: "Test", code: -999)
  //    )
  //
  //    // Should not be cached and not downloading anymore
  //    try await CacheHelpers.waitForNotCached(podcastEpisode.id)
  //    try await CacheHelpers.waitForCacheStateNotDownloading(podcastEpisode.id)
  //  }
  //
  //  // MARK: - Additional Edge Cases
  //
  //  @Test("dequeue while onDeck does not clear cache")
  //  func dequeueWhileOnDeckDoesNotClearCache() async throws {
  //    // Create episode already marked as cached in DB
  //    let data = CacheHelpers.createRandomData()
  //    let cachedName = "cached-episode.mp3"
  //    let pe = try await Create.podcastEpisode(
  //      Create.unsavedEpisode(cachedFilename: cachedName)
  //    )
  //
  //    // Write the cached file to disk
  //    let fileURL = CacheManager.resolveCachedFilepath(for: cachedName)
  //    try await Container.shared.podFileManager().writeData(data, to: fileURL)
  //
  //    // Queue it so CacheManager observes it
  //    try await queue.unshift(pe.id)
  //
  //    // Put the episode on-deck (simulating currently loaded/playing)
  //    let ps: PlayState = Container.shared.playState()
  //    let od = OnDeck(
  //      episodeID: pe.id,
  //      feedURL: pe.podcast.feedURL,
  //      guid: pe.episode.unsaved.guid,
  //      podcastTitle: pe.podcast.title,
  //      podcastURL: pe.podcast.link,
  //      episodeTitle: pe.episode.title,
  //      duration: pe.episode.duration,
  //      image: nil,
  //      mediaURL: pe.episode.mediaURL,
  //      pubDate: pe.episode.pubDate
  //    )
  //    ps.setOnDeck(od)
  //
  //    // Dequeue and verify the file was NOT removed because onDeck protects it
  //    try await queue.dequeue(pe.id)
  //    try await Wait.until(
  //      { try await self.repo.episode(pe.id)?.queued == false },
  //      { "Expected episode dequeued" }
  //    )
  //
  //    try await CacheHelpers.waitForCachedFile(cachedName)
  //    #expect(try await repo.episode(pe.id)?.cachedFilename == cachedName)
  //  }
  //
  //  @Test("clearCache returns false if queued")
  //  func clearCacheReturnsFalseIfQueued() async throws {
  //    let pe = try await Create.podcastEpisode(
  //      Create.unsavedEpisode(queueOrder: 0, cachedFilename: "cached.mp3")
  //    )
  //    let didClear = try await cacheManager.clearCache(for: pe.id)
  //    #expect(didClear == false)
  //    #expect(try await repo.episode(pe.id)?.cachedFilename != nil)
  //  }
  //
  //  @Test("clearCache returns false if not cached")
  //  func clearCacheReturnsFalseIfNotCached() async throws {
  //    let pe = try await Create.podcastEpisode()
  //    let didClear = try await cacheManager.clearCache(for: pe.id)
  //    #expect(didClear == false)
  //    #expect(try await repo.episode(pe.id)?.cachedFilename == nil)
  //  }
  //
  //  @Test("clearCache nulls DB when file missing")
  //  func clearCacheNullsDBWhenFileMissing() async throws {
  //    let pe = try await Create.podcastEpisode(
  //      Create.unsavedEpisode(cachedFilename: "missing.mp3")
  //    )
  //    let didClear = try await cacheManager.clearCache(for: pe.id)
  //    #expect(didClear == true)
  //    #expect(try await repo.episode(pe.id)?.cachedFilename == nil)
  //  }
  //
  //  @Test("progress is cleared on dequeue mid-download (explicit)")
  //  func progressClearedOnDequeue() async throws {
  //    let pe = try await Create.podcastEpisode()
  //
  //    try await queue.unshift(pe.id)
  //    try await CacheHelpers.waitForCacheStateDownloading(pe.id)
  //
  //    // Set progress and then dequeue, it should clear
  //    cacheState.updateProgress(for: pe.id, progress: 0.42)
  //    try await queue.dequeue(pe.id)
  //    try await CacheHelpers.waitForCacheStateNotDownloading(pe.id)
  //
  //    #expect(cacheState.progress(pe.id) == nil)
  //  }
  //
  //  @Test("already cached episode added to queue does not prefetch artwork")
  //  func alreadyCachedDoesNotPrefetchArtwork() async throws {
  //    let pe = try await Create.podcastEpisode(
  //      Create.unsavedEpisode(image: URL.valid(), cachedFilename: "already-cached.mp3")
  //    )
  //
  //    let img = pe.image
  //    #expect(await imageFetcher.prefetchCounts[img] == nil)
  //
  //    try await queue.unshift(pe.id)
  //
  //    // Image prefetch should be skipped because cachedFilename exists
  //    let count = await imageFetcher.prefetchCounts[img]
  //    #expect(count == nil || count == 0)
  //  }
  //
  //  @Test("replace clears removed caches and keeps remaining")
  //  func replaceClearsRemovedKeepsRemaining() async throws {
  //    let (ep1, ep2) = try await Create.twoPodcastEpisodes(
  //      try Create.unsavedEpisode(cachedFilename: "one.mp3"),
  //      try Create.unsavedEpisode(cachedFilename: "two.mp3")
  //    )
  //
  //    // Queue both and simulate background completion for each
  //    try await queue.unshift(ep1.id)
  //    _ = try await CacheHelpers.waitForScheduledTaskID(ep1.id)
  //    try await queue.unshift(ep2.id)
  //    _ = try await CacheHelpers.waitForScheduledTaskID(ep2.id)
  //
  //    let d1 = CacheHelpers.createRandomData()
  //    let d2 = CacheHelpers.createRandomData()
  //    try await CacheHelpers.simulateBackgroundFinish(ep1.id, data: d1)
  //    try await CacheHelpers.simulateBackgroundFinish(ep2.id, data: d2)
  //
  //    let f1 = try await CacheHelpers.waitForCached(ep1.id)
  //    let f2 = try await CacheHelpers.waitForCached(ep2.id)
  //    try await CacheHelpers.waitForCachedFile(f1)
  //    try await CacheHelpers.waitForCachedFile(f2)
  //
  //    // Replace queue with only ep2, ep1 should be cleared
  //    try await queue.replace([ep2.id])
  //
  //    try await CacheHelpers.waitForCachedFileRemoved(f1)
  //    try await CacheHelpers.waitForCachedFile(f2)
  //  }
  //
  //  @Test("generateCacheFilename falls back to mp3 and preserves extension")
  //  func generateCacheFilenameFallbackAndPreserve() async throws {
  //    let noExt = try await Create.podcastEpisode(
  //      Create.unsavedEpisode(media: MediaURL(URL(string: "https://a.b/c/d")!))
  //    )
  //    let withExt = try await Create.podcastEpisode(
  //      Create.unsavedEpisode(media: MediaURL(URL(string: "https://a.b/c/d.wav")!))
  //    )
  //
  //    let name1 = CacheManager.generateCacheFilename(for: noExt.episode)
  //    let name2 = CacheManager.generateCacheFilename(for: withExt.episode)
  //    #expect(name1.hasSuffix(".mp3"))
  //    #expect(name2.hasSuffix(".wav"))
  //  }
  //
  //  @Test("requeue immediately after dequeue re-caches")
  //  func requeueAfterDequeueReCaches() async throws {
  //    let pe = try await Create.podcastEpisode()
  //
  //    try await queue.unshift(pe.id)
  //    let d1 = CacheHelpers.createRandomData()
  //    try await CacheHelpers.simulateBackgroundFinish(pe.id, data: d1)
  //    let f1 = try await CacheHelpers.waitForCached(pe.id)
  //    try await CacheHelpers.waitForCachedFile(f1)
  //
  //    try await queue.dequeue(pe.id)
  //    try await CacheHelpers.waitForCachedFileRemoved(f1)
  //
  //    try await queue.unshift(pe.id)
  //    _ = try await CacheHelpers.waitForScheduledTaskID(pe.id)
  //    let d2 = CacheHelpers.createRandomData()
  //    try await CacheHelpers.simulateBackgroundFinish(pe.id, data: d2)
  //    let f2 = try await CacheHelpers.waitForCached(pe.id)
  //    try await CacheHelpers.waitForCachedFile(f2)
  //  }
}
