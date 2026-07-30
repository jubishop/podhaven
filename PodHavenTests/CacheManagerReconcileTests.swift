// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of CacheManager stale-download reconciliation", .container)
struct CacheManagerReconcileTests {
  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState

  private var session: FakeDataFetchable {
    Container.shared.cacheManagerSession() as! FakeDataFetchable
  }

  @Test("start() clears a stranded downloading flag but keeps a live download")
  func reconcilesStaleDownloadsOnStart() async throws {
    // A live download: a real task exists for it in the session.
    let live = try await Create.podcastEpisode()
    try await CacheHelpers.downloadToCache(live.id)

    // A stranded flag: downloading == true with no backing task (force-quit).
    let stale = try await Create.podcastEpisode()
    try await repo.updateDownloading(stale.id, downloading: true)

    cacheManager.start()

    try await CacheHelpers.waitForNotDownloading(stale.id)
    let liveEpisode = try await repo.episode(live.id)
    #expect(liveEpisode?.downloading == true)
  }

  @Test("start() resumes a stranded download for the current episode")
  func resumesStrandedCurrentEpisodeOnStart() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    // Stranded flag (force-quit) on the currently-playing episode.
    try await repo.updateDownloading(podcastEpisode.id, downloading: true)
    sharedState.currentEpisodeID = podcastEpisode.id

    cacheManager.start()

    // Reconcile must clear the stale flag before the observer runs, so it
    // starts a real download instead of skipping it as "already caching".
    let taskID = try await CacheHelpers.waitForDownloadTask(podcastEpisode.id)
    try await CacheHelpers.waitForResumed(taskID)
  }

  @Test("start() preserves finalization after URLSession drops its completed task")
  func preservesFinalizationAfterCompletedTaskDisappears() async throws {
    let assetStarted = AsyncSemaphore(value: 0)
    let assetRelease = AsyncSemaphore(value: 0)
    await episodeAssetLoader.setDefaultHandler { _ in
      assetStarted.signal()
      try await assetRelease.waitUnlessCancelled()
      return (true, CMTime.seconds(30))
    }

    let finalizing = try await Create.podcastEpisode()
    let originalTaskID = try await CacheHelpers.downloadToCache(finalizing.id)
    let observerBootstrap = try await Create.podcastEpisode()
    let observerBarrier = try await Create.podcastEpisode()

    Container.shared.cacheManager.reset(.scope)
    let relaunchedCacheManager = Container.shared.cacheManager()

    async let finalization = CacheHelpers.simulateBackgroundFinish(originalTaskID)
    await assetStarted.wait()
    #expect(await session.downloadTasks()[id: originalTaskID] == nil)

    sharedState.currentEpisodeID = observerBootstrap.id
    relaunchedCacheManager.start()
    _ = try await CacheHelpers.waitForDownloadTask(observerBootstrap.id)

    sharedState.currentEpisodeID = finalizing.id
    sharedState.currentEpisodeID = observerBarrier.id
    _ = try await CacheHelpers.waitForDownloadTask(observerBarrier.id)

    let finalizingDescription = String(finalizing.id.rawValue)
    let outstandingTasks = await session.downloadTasks()
    #expect(!outstandingTasks.contains { $0.taskDescription == finalizingDescription })

    assetRelease.signal()
    _ = try await finalization
    _ = try await CacheHelpers.waitForCached(finalizing.id)
  }
}
