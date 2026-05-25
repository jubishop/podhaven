// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

// Separate suite because cold-launch simulation requires seeding defaults
// before `sharedState` is resolved — incompatible with the auto-`start()` in
// `CacheManagerTests.init`.
@Suite("of CacheManager cold-launch tests", .container)
@MainActor class CacheManagerColdLaunchTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.stateManager) private var stateManager

  private var sharedState: SharedState {
    Container.shared.sharedState()
  }

  @Test("clearCache does nothing if episode is currentEpisodeID but onDeck is nil")
  func clearCacheDoesNothingIfEpisodeIsCurrentEpisodeIDButOnDeckIsNil() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    podcastEpisode.id.store(
      to: Container.shared.standardDefaults(),
      forKey: "currentEpisodeID"
    )

    stateManager.start()
    cacheManager.start()

    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)
    try await CacheHelpers.simulateBackgroundFinish(taskID)
    try await CacheHelpers.waitForCached(podcastEpisode.id)

    #expect(sharedState.onDeck == nil)
    #expect(sharedState.currentEpisodeID == podcastEpisode.id)

    #expect(try await cacheManager.clearCache(for: podcastEpisode.id) == nil)
    try await CacheHelpers.waitForCached(podcastEpisode.id)
  }
}
