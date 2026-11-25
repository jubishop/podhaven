// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of Background command center launch tests", .container)
@MainActor struct BackgroundCommandCenterLaunchTests {
  private var mpRemoteCommandCenter: FakeMPRemoteCommandCenter {
    Container.shared.mpRemoteCommandCenter() as! FakeMPRemoteCommandCenter
  }

  private func registerRemoteCommandHandlers() {
    // The app host may have already run bootstrap, but `.container` swaps in a
    // fresh fake command center for each test, so register handlers explicitly.
    CommandCenter.registerRemoteCommandHandlers()
  }

  // Simulate the cold-launch state where `currentEpisodeID` was persisted on a
  // prior run. Must be called before anything resolves `sharedState`.
  private func seedPersistedCurrentEpisodeID(_ id: Episode.ID) {
    id.store(to: Container.shared.standardDefaults(), forKey: "currentEpisodeID")
  }

  @Test("first toggle command prepares playback before toggling")
  func firstToggleCommandPreparesPlaybackBeforeToggling() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      try Create.unsavedEpisode(currentTime: .seconds(10))
    )
    seedPersistedCurrentEpisodeID(podcastEpisode.id)

    registerRemoteCommandHandlers()

    mpRemoteCommandCenter.fireTogglePlayPause()

    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitForCurrentItem(podcastEpisode.episode.mediaURL)
    try await Wait.until(
      { @MainActor in
        (Container.shared.avPlayer() as! FakeAVPlayer).timeControlStatus == .playing
      },
      { @MainActor in
        let status = (Container.shared.avPlayer() as! FakeAVPlayer).timeControlStatus
        return "Player status is: \(status), Expected: playing"
      }
    )
  }

  @Test("remote commands reach playback in the order they arrive")
  func remoteCommandsReachPlaybackInOrder() async throws {
    let avPlayer = Container.shared.avPlayer() as! FakeAVPlayer
    registerRemoteCommandHandlers()
    let rates: [Float] = [0.8, 0.9, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0]
    let commandRates = rates + rates.reversed() + rates + rates.reversed()

    for rate in commandRates {
      mpRemoteCommandCenter.fireChangePlaybackRate(rate)
    }

    try await Wait.until(
      { @MainActor in avPlayer.defaultRateRequests.filter(rates.contains).count == commandRates.count },
      { @MainActor in "Applied rates: \(avPlayer.defaultRateRequests)" }
    )
    #expect(avPlayer.defaultRateRequests.filter(rates.contains) == commandRates)
  }

  @Test("first skip command prepares playback before seeking")
  func firstSkipCommandPreparesPlaybackBeforeSeeking() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      try Create.unsavedEpisode(currentTime: .seconds(10))
    )
    seedPersistedCurrentEpisodeID(podcastEpisode.id)

    registerRemoteCommandHandlers()

    mpRemoteCommandCenter.fireSkipForward(TimeInterval.seconds(5))

    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitForCurrentItem(podcastEpisode.episode.mediaURL)
    try await PlayHelpers.waitFor(.seconds(15))
  }
}
