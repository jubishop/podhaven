// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of Command Center isolation tests", .container)
@MainActor struct CommandCenterIsolationTests {
  @DynamicInjected(\.fakeAudioSession) private var audioSession
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.notifier) private var notifier
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.stateManager) private var stateManager
  @DynamicInjected(\.userSettings) private var userSettings

  private var mpRemoteCommandCenter: FakeMPRemoteCommandCenter {
    Container.shared.mpRemoteCommandCenter() as! FakeMPRemoteCommandCenter
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
    PlayHelpers.setupCommandHandling()
  }

  @Test("settings changes update remote commands on the main thread")
  func settingsChangesUpdateRemoteCommandsOnMainThread() async throws {
    userSettings.$skipForwardInterval.new(45)
    userSettings.$skipBackwardInterval.new(10)
    userSettings.$nextTrackBehavior.new(.nextEpisode)
    userSettings.$commandCenterScrubbingEnabled.new(false)

    try await Wait.until(
      { @MainActor in
        self.mpRemoteCommandCenter.skipForward.preferredIntervals.map(\.doubleValue) == [45]
          && self.mpRemoteCommandCenter.skipBackward.preferredIntervals.map(\.doubleValue) == [10]
          && self.mpRemoteCommandCenter.nextTrack.isEnabled == false
          && self.mpRemoteCommandCenter.changePlaybackPosition.isEnabled == false
      },
      { "Expected remote commands to reflect the changed settings" }
    )
    #expect(mpRemoteCommandCenter.writes.offMain == [])
  }

  @Test("loading an episode updates remote commands on the main thread")
  func loadingEpisodeUpdatesRemoteCommandsOnMainThread() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.load(podcastEpisode)

    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.previousTrack.isEnabled },
      { "Expected previousTrack to be enabled once an episode is on deck" }
    )
    #expect(mpRemoteCommandCenter.writes.offMain == [])
  }

  @Test("media services reset re-registers remote commands on the main thread")
  func mediaServicesResetReregistersRemoteCommandsOnMainThread() async throws {
    await playManager.start()
    let initialConfigureCallCount = await audioSession.configureCallCount

    notifier.continuation(for: AVAudioSession.mediaServicesWereResetNotification)
      .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))

    try await PlayHelpers.waitForConfigureCallCount(atLeast: initialConfigureCallCount + 1)
    #expect(mpRemoteCommandCenter.writes.offMain == [])
  }
}
