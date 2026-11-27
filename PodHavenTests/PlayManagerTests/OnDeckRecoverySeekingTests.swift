// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of On Deck recovery seeking tests", .container)
@MainActor struct OnDeckRecoverySeekingTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager

  private let duration = CMTime.seconds(240)
  private let savedTime = CMTime.seconds(100)

  private var avPlayer: FakeAVPlayer {
    Container.shared.avPlayer() as! FakeAVPlayer
  }
  private var mpRemoteCommandCenter: FakeMPRemoteCommandCenter {
    Container.shared.mpRemoteCommandCenter() as! FakeMPRemoteCommandCenter
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
    PlayHelpers.setupCommandHandling()
  }

  @Test(
    "seeks and skips awaiting a recovery reload move the position Play resumes from",
    .timeLimit(.minutes(5)),
    arguments: [OnDeckRecoveryState.Cause.failedRestore, .mediaServicesReset]
  )
  func seeksAndSkipsMoveResumePosition(cause: OnDeckRecoveryState.Cause) async throws {
    let podcastEpisode = try await awaitRecoveryReload(cause)

    await playManager.seekForward(30)
    try await waitForPosition(.seconds(130), of: podcastEpisode)

    await playManager.seekBackward(15)
    try await waitForPosition(.seconds(115), of: podcastEpisode)

    let scrubTime = CMTime.seconds(180)
    await playManager.seek(to: scrubTime)
    try await waitForPosition(scrubTime, of: podcastEpisode)

    await playManager.play()

    try await PlayHelpers.awaitStatus(.playing)
    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    #expect(avPlayer.seekRequests.last == scrubTime)
    try await PlayHelpers.waitFor(scrubTime)
  }

  @Test(
    "a skip past the end awaiting a recovery reload lands at the duration",
    arguments: [OnDeckRecoveryState.Cause.failedRestore, .mediaServicesReset]
  )
  func skipPastEndLandsAtDuration(cause: OnDeckRecoveryState.Cause) async throws {
    let podcastEpisode = try await awaitRecoveryReload(cause)

    await playManager.seekForward(duration.seconds)

    try await waitForPosition(duration, of: podcastEpisode)
    #expect(sharedState.onDeck?.id == podcastEpisode.id)
    let episode = try #require(try await repo.episode(podcastEpisode.id))
    #expect(!episode.finished)
  }

  @Test(
    "remote skips and scrubs awaiting a recovery reload move the position",
    arguments: [OnDeckRecoveryState.Cause.failedRestore, .mediaServicesReset]
  )
  func remoteSkipsAndScrubsMovePosition(cause: OnDeckRecoveryState.Cause) async throws {
    let podcastEpisode = try await awaitRecoveryReload(cause)

    mpRemoteCommandCenter.fireSkipForward(30)
    try await waitForPosition(.seconds(130), of: podcastEpisode)

    mpRemoteCommandCenter.fireSkipBackward(15)
    try await waitForPosition(.seconds(115), of: podcastEpisode)

    // The episode is well past its start, so a scrub to its end is deliberate.
    let nearEnd = duration - .seconds(1)
    mpRemoteCommandCenter.fireSeek(to: nearEnd.seconds)
    try await waitForPosition(nearEnd, of: podcastEpisode)
  }

  // MARK: - Helpers

  private func awaitRecoveryReload(_ cause: OnDeckRecoveryState.Cause) async throws
    -> PodcastEpisode
  {
    try await PlayHelpers.awaitOnDeckRecoveryReload(
      cause,
      duration: duration,
      currentTime: savedTime
    )
  }

  private func waitForPosition(_ time: CMTime, of podcastEpisode: PodcastEpisode)
    async throws
  {
    try await PlayHelpers.waitFor(time)
    try await PlayHelpers.waitForEpisode(podcastEpisode.id, attribute: \.currentTime, toBe: time)
  }
}
