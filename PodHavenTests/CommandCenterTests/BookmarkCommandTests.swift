// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import MediaPlayer
import Testing

@testable import PodHaven

@Suite("of Bookmark command tests", .container)
@MainActor struct BookmarkCommandTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager

  private var mpRemoteCommandCenter: FakeMPRemoteCommandCenter {
    Container.shared.mpRemoteCommandCenter() as! FakeMPRemoteCommandCenter
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
    PlayHelpers.setupCommandHandling()
  }

  @Test("bookmark command is enabled")
  func bookmarkCommandIsEnabled() async throws {
    #expect(mpRemoteCommandCenter.bookmark.isEnabled == true)
  }

  @Test("bookmark saves the on-deck episode in the cache")
  func bookmarkSavesOnDeckEpisodeInCache() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.load(podcastEpisode)
    #expect(try await repo.episode(podcastEpisode.id)?.saveInCache == false)

    mpRemoteCommandCenter.fireBookmark()

    try await Wait.until(
      { try await self.repo.episode(podcastEpisode.id)?.saveInCache == true },
      { "Expected on-deck episode to be saved in cache after bookmark" }
    )
    try await CacheHelpers.waitForDownloading(podcastEpisode.id)
  }
}
