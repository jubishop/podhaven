// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of CacheManager stale-download reconciliation", .container)
struct CacheManagerReconcileTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState

  @Test("start() clears a stranded downloading flag but keeps a live download")
  func reconcilesStaleDownloadsOnStart() async throws {
    // A live download: a real task exists for it in the session.
    let live = try await Create.podcastEpisode()
    try await CacheHelpers.downloadToCache(live.id)

    // A stranded flag: downloading == true with no backing task, as a
    // force-quit mid-download leaves it.
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

    // Stranded flag with no backing task, as a force-quit mid-download leaves
    // it, on the episode the user is currently listening to.
    try await repo.updateDownloading(podcastEpisode.id, downloading: true)
    sharedState.currentEpisodeID = podcastEpisode.id

    cacheManager.start()

    // Reconcile must clear the stale flag before the current-episode observer
    // runs, so the observer starts a real download instead of skipping it as
    // "already caching".
    let taskID = try await CacheHelpers.waitForDownloadTask(podcastEpisode.id)
    try await CacheHelpers.waitForResumed(taskID)
  }
}
