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

  @Test("bookmark command is enabled with a Save in Cache title")
  func bookmarkCommandIsEnabled() async throws {
    #expect(mpRemoteCommandCenter.bookmark.isEnabled == true)
    #expect(mpRemoteCommandCenter.bookmark.localizedTitle == "Save in Cache")
    #expect(mpRemoteCommandCenter.bookmark.localizedShortTitle == "Save")
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

  @Test("bookmark toggles a saved on-deck episode back out of the cache")
  func bookmarkTogglesSavedEpisodeOff() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.load(podcastEpisode)

    mpRemoteCommandCenter.fireBookmark()
    try await Wait.until(
      { try await self.repo.episode(podcastEpisode.id)?.saveInCache == true },
      { "Expected on-deck episode to be saved after first bookmark" }
    )

    mpRemoteCommandCenter.fireBookmark()
    try await Wait.until(
      { try await self.repo.episode(podcastEpisode.id)?.saveInCache == false },
      { "Expected on-deck episode to be unsaved after second bookmark" }
    )
  }

  @Test("bookmark isActive reflects whether the on-deck episode is saved")
  func bookmarkIsActiveReflectsSavedState() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.load(podcastEpisode)
    #expect(mpRemoteCommandCenter.bookmark.isActive == false)

    mpRemoteCommandCenter.fireBookmark()
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.bookmark.isActive == true },
      { "Expected bookmark isActive to become true after saving" }
    )

    mpRemoteCommandCenter.fireBookmark()
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.bookmark.isActive == false },
      { "Expected bookmark isActive to become false after unsaving" }
    )
  }
}
