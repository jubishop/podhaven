// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of CacheManager stale-download reconciliation", .container)
struct CacheManagerReconcileTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.repo) private var repo

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
}
