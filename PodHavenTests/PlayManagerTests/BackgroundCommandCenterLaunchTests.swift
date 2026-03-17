// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("Background command center launch tests", .container)
@MainActor struct BackgroundCommandCenterLaunchTests {
  @DynamicInjected(\.sharedState) private var sharedState

  private var mpRemoteCommandCenter: FakeMPRemoteCommandCenter {
    Container.shared.mpRemoteCommandCenter() as! FakeMPRemoteCommandCenter
  }

  private func registerRemoteCommandHandlers() {
    // The app host may have already run bootstrap, but `.container` swaps in a
    // fresh fake command center for each test, so register handlers explicitly.
    CommandCenter.registerRemoteCommandHandlers()
  }

  @Test("first toggle command prepares playback before toggling")
  func firstToggleCommandPreparesPlaybackBeforeToggling() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      try Create.unsavedEpisode(currentTime: .seconds(10))
    )
    sharedState.currentEpisodeID = podcastEpisode.id

    registerRemoteCommandHandlers()

    mpRemoteCommandCenter.fireTogglePlayPause()

    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitForCurrentItem(podcastEpisode.episode.mediaURL)
    try await PlayHelpers.waitFor(.playing)
  }

  @Test("first skip command prepares playback before seeking")
  func firstSkipCommandPreparesPlaybackBeforeSeeking() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      try Create.unsavedEpisode(currentTime: .seconds(10))
    )
    sharedState.currentEpisodeID = podcastEpisode.id

    registerRemoteCommandHandlers()

    mpRemoteCommandCenter.fireSkipForward(TimeInterval.seconds(5))

    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitForCurrentItem(podcastEpisode.episode.mediaURL)
    try await PlayHelpers.waitFor(.seconds(15))
  }
}
