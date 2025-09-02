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
  @DynamicInjected(\.cacheState) private var cacheState
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  private var imageFetcher: FakeImageFetcher {
    Container.shared.imageFetcher() as! FakeImageFetcher
  }
  private var sleeper: FakeSleeper {
    Container.shared.sleeper() as! FakeSleeper
  }

  init() async throws {
    await sleeper.skipAllSleeps()
    try await cacheManager.start()
  }

  // MARK: - Queue Observation Tests

  @Test("episode added to queue gets cached")
  func episodeAddedToQueueGetsCached() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    let data = CacheHelpers.createRandomData()

    try await queue.unshift(podcastEpisode.id)
    try await CacheHelpers.simulateBackgroundFinish(podcastEpisode.id, data: data)

    let fileName = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(fileName)

    let actualData = try await CacheHelpers.readCachedFileData(fileName)
    #expect(actualData == data)
  }

  @Test("episode removed from queue gets cache cleared")
  func episodeRemovedFromQueueGetsCacheCleared() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    // First cache the episode
    try await queue.unshift(podcastEpisode.id)
    let fileName = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(fileName)

    // Remove from queue and verify cache is cleared
    try await queue.dequeue(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFileRemoved(fileName)
  }

  @Test("episode dequeued mid-download does not get cached when download completes")
  func episodeDequeuedMidDownloadDoesNotGetCachedWhenDownloadCompletes() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await queue.unshift(podcastEpisode.id)
    try await CacheHelpers.waitForCacheStateDownloading(podcastEpisode.id)

    try await queue.dequeue(podcastEpisode.id)
    try await CacheHelpers.waitForCacheStateNotDownloading(podcastEpisode.id)

    // Simulate finish should be ignored
    let data = CacheHelpers.createRandomData()
    try await CacheHelpers.simulateBackgroundFinish(podcastEpisode.id, data: data)
  }

  // MARK: - Artwork Prefetching

  @Test("episode artwork is prefetched when episode is cached")
  func episodeArtworkIsPrefetchedWhenEpisodeIsCached() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await queue.unshift(podcastEpisode.id)
    let fileName = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(fileName)

    #expect(await imageFetcher.prefetchCounts[podcastEpisode.image] == 1)
  }

  // MARK: - CacheState Tests

  @Test("CacheState is updated when episode starts downloading")
  func cacheStateIsUpdatedWhenEpisodeStartsDownloading() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    // Initially, episode should not be downloading in CacheState
    #expect(!cacheState.isDownloading(podcastEpisode.id))

    try await queue.unshift(podcastEpisode.id)

    // Verify CacheState shows episode as downloading
    try await CacheHelpers.waitForCacheStateDownloading(podcastEpisode.id)

    // Complete the download via simulation
    let data = CacheHelpers.createRandomData()
    try await CacheHelpers.simulateBackgroundFinish(podcastEpisode.id, data: data)

    // Verify CacheState shows episode as not downloading
    try await CacheHelpers.waitForCacheStateNotDownloading(podcastEpisode.id)
  }

  @Test("CacheState is updated when episode download is cancelled")
  func cacheStateIsUpdatedWhenEpisodeDownloadIsCancelled() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await queue.unshift(podcastEpisode.id)

    // Verify CacheState shows episode as downloading
    try await CacheHelpers.waitForCacheStateDownloading(podcastEpisode.id)

    // Remove from queue to cancel download
    try await queue.dequeue(podcastEpisode.id)

    // Verify CacheState shows episode as not downloading
    try await CacheHelpers.waitForCacheStateNotDownloading(podcastEpisode.id)
  }

  @Test("CacheState tracks multiple episodes downloading simultaneously")
  func cacheStateTracksMultipleEpisodesDownloadingSimultaneously() async throws {
    // Create 3 episodes
    let episode1 = try await Create.podcastEpisode()
    let episode2 = try await Create.podcastEpisode()
    let episode3 = try await Create.podcastEpisode()

    // Add all to queue
    try await queue.unshift(episode1.id)
    try await queue.unshift(episode2.id)
    try await queue.unshift(episode3.id)

    // All should be downloading
    try await CacheHelpers.waitForCacheStateDownloading(episode1.id)
    try await CacheHelpers.waitForCacheStateDownloading(episode2.id)
    try await CacheHelpers.waitForCacheStateDownloading(episode3.id)

    // Complete episode1
    let data1 = CacheHelpers.createRandomData()
    try await CacheHelpers.simulateBackgroundFinish(episode1.id, data: data1)
    try await CacheHelpers.waitForCached(episode1.id)
    try await CacheHelpers.waitForCacheStateNotDownloading(episode1.id)

    // Episode2 and episode3 should still be downloading
    #expect(cacheState.isDownloading(episode2.id))
    #expect(cacheState.isDownloading(episode3.id))

    // Complete remaining episodes
    let data2 = CacheHelpers.createRandomData()
    let data3 = CacheHelpers.createRandomData()
    try await CacheHelpers.simulateBackgroundFinish(episode2.id, data: data2)
    try await CacheHelpers.waitForCached(episode2.id)
    try await CacheHelpers.waitForCacheStateNotDownloading(episode2.id)
    try await CacheHelpers.simulateBackgroundFinish(episode3.id, data: data3)
    try await CacheHelpers.waitForCached(episode3.id)
    try await CacheHelpers.waitForCacheStateNotDownloading(episode3.id)
  }

  // MARK: - Background Download (Simulated)

  @Test("progress updates via fake harness and clears on finish")
  func progressViaHarnessUpdatesCacheState() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    // Queue the episode and wait for scheduling
    try await queue.unshift(podcastEpisode.id)
    try await CacheHelpers.waitForCacheStateDownloading(podcastEpisode.id)

    // Obtain the scheduled background task ID from CacheState
    let cs: CacheState = await Container.shared.cacheState()
    let maybeTaskID = await cs.getBackgroundTaskIdentifier(podcastEpisode.id)
    #expect(maybeTaskID != nil)
    guard let taskID = maybeTaskID else { return }

    // Simulate progress through the fake harness
    if let fake = Container.shared.cacheBackgroundFetchable() as? FakeDataFetchable {
      await fake.progressDownload(taskID: taskID, totalBytesWritten: 50, totalBytesExpectedToWrite: 100)
    }

    // Verify progress reflects 50%
    #expect(await cs.progress(podcastEpisode.id) == 0.5)

    // Finish and verify progress cleared
    let data = CacheHelpers.createRandomData(size: 128)
    try await CacheHelpers.simulateBackgroundFinish(podcastEpisode.id, data: data)
    try await CacheHelpers.waitForCacheStateNotDownloading(podcastEpisode.id)
    #expect(await cs.progress(podcastEpisode.id) == nil)
  }

  @Test("progress is updated and cleared on finish")
  func progressIsUpdatedAndClearedOnFinish() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    // Queue the episode (kicks off scheduling, CacheState will show downloading)
    try await queue.unshift(podcastEpisode.id)
    try await CacheHelpers.waitForCacheStateDownloading(podcastEpisode.id)

    // Simulate progress by calling CacheState directly using MediaGUID
    let mg = podcastEpisode.episode.unsaved.id
    let cs: CacheState = await Container.shared.cacheState()
    await cs.updateProgress(for: mg, progress: 0.42)

    // Assert progress visible
    #expect(await cs.progress(podcastEpisode.id) == 0.42)

    // Finish download and ensure progress cleared
    let data = CacheHelpers.createRandomData(size: 256)
    try await CacheHelpers.simulateBackgroundFinish(podcastEpisode.id, data: data)
    try await CacheHelpers.waitForCacheStateNotDownloading(podcastEpisode.id)
    #expect(await cs.progress(podcastEpisode.id) == nil)
  }

  @Test("background delegate caches file when queued")
  func backgroundDelegateCachesWhenQueued() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    // Ensure episode is queued so delegate caches on finish
    try await queue.unshift(podcastEpisode.id)

    // Simulate background completion
    let data = CacheHelpers.createRandomData(size: 2048)
    try await CacheHelpers.simulateBackgroundFinish(podcastEpisode.id, data: data)

    // Validate cached filename and file contents
    let fileName = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(fileName)
    let actualData = try await CacheHelpers.readCachedFileData(fileName)
    #expect(actualData == data)
  }

  @Test("background delegate skips caching when dequeued before finish")
  func backgroundDelegateSkipsWhenDequeuedBeforeFinish() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    // Queue then dequeue before simulating finish
    try await queue.unshift(podcastEpisode.id)
    try await queue.dequeue(podcastEpisode.id)

    // Simulate background completion
    let data = CacheHelpers.createRandomData(size: 1024)
    try await CacheHelpers.simulateBackgroundFinish(podcastEpisode.id, data: data)

    // Should not be cached
    try await CacheHelpers.waitForNotCached(podcastEpisode.id)
  }

  @Test("background delegate marks failure and clears state")
  func backgroundDelegateMarksFailureAndClearsState() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    // Mark as queued to simulate a user-initiated download
    try await queue.unshift(podcastEpisode.id)

    // Simulate an error from background session
    try await CacheHelpers.simulateBackgroundFailure(
      podcastEpisode.id,
      error: NSError(domain: "Test", code: -999)
    )

    // Should not be cached and not downloading anymore
    try await CacheHelpers.waitForNotCached(podcastEpisode.id)
    try await CacheHelpers.waitForCacheStateNotDownloading(podcastEpisode.id)
  }
}
