// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import MediaPlayer
import Testing

@testable import PodHaven

@Suite("of Next track command tests", .container)
@MainActor struct NextTrackCommandTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager

  private var mpRemoteCommandCenter: FakeMPRemoteCommandCenter {
    Container.shared.mpRemoteCommandCenter() as! FakeMPRemoteCommandCenter
  }
  private var nowPlayingInfo: [String: Any?]? {
    Container.shared.mpNowPlayingInfoCenter().nowPlayingInfo
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
    PlayHelpers.setupCommandHandling()
  }

  // MARK: - Next Track Command

  @Test("nextTrackCommand is disabled when queue is empty")
  func nextTrackCommandIsDisabledWhenQueueIsEmpty() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)

    // Wait for queue observation to update command state
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == false },
      { "Expected nextTrackCommand to be disabled when queue is empty" }
    )
  }

  @Test("nextTrackCommand is enabled when queue has episodes")
  func nextTrackCommandIsEnabledWhenQueueHasEpisodes() async throws {

    await playManager.start()
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    try await playManager.load(playingEpisode)

    // Wait for queue observation to update command state
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == true },
      { "Expected nextTrackCommand to be enabled when queue has episodes" }
    )
  }

  @Test("nextTrackCommand is disabled after queue becomes empty")
  func nextTrackCommandIsDisabledAfterQueueBecomesEmpty() async throws {

    await playManager.start()
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    try await playManager.load(playingEpisode)

    // Wait for nextTrackCommand to be enabled
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == true },
      { "Expected nextTrackCommand to be enabled" }
    )

    // Remove episode from queue
    try await queue.dequeue(queuedEpisode.id)

    // Wait for nextTrackCommand to be disabled
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == false },
      { "Expected nextTrackCommand to be disabled after queue becomes empty" }
    )
  }

  @Test("nextTrackCommand advances to next episode when enabled")
  func nextTrackCommandAdvancesToNextEpisodeWhenEnabled() async throws {

    await playManager.start()
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    try await playManager.load(playingEpisode)
    await playManager.play()

    // Wait for nextTrackCommand to be enabled
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == true },
      { "Expected nextTrackCommand to be enabled" }
    )

    // Fire next track command
    mpRemoteCommandCenter.fireNextTrack()

    // Verify we advanced to the next episode
    try await PlayHelpers.waitForOnDeck(queuedEpisode)
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForCurrentItem(queuedEpisode.episode.mediaURL)
  }

  @Test("queue count updates MPNowPlayingInfoPropertyPlaybackQueueCount")
  func queueCountUpdatesMPNowPlayingInfoPropertyPlaybackQueueCount() async throws {

    await playManager.start()
    let (playingEpisode, queuedEpisode1, queuedEpisode2) =
      try await Create.threePodcastEpisodes()

    try await playManager.load(playingEpisode)

    // Wait for queue count to be 1 (current item only)
    try await Wait.until(
      { @MainActor in
        self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int == 1
      },
      { @MainActor in
        """
        Expected queue count to be 1, got \
        \(String(describing: self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount]))
        """
      }
    )

    // Add first episode to queue
    try await queue.unshift(queuedEpisode1.id)

    // Wait for queue count to be 2 (current + 1 queued)
    try await Wait.until(
      { @MainActor in
        self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int == 2
      },
      { @MainActor in
        """
        Expected queue count to be 2, got \
        \(String(describing: self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount]))
        """
      }
    )

    // Add second episode to queue
    try await queue.unshift(queuedEpisode2.id)

    // Wait for queue count to be 3 (current + 2 queued)
    try await Wait.until(
      { @MainActor in
        self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int == 3
      },
      { @MainActor in
        """
        Expected queue count to be 3, got \
        \(String(describing: self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount]))
        """
      }
    )

    // Remove first episode from queue
    try await queue.dequeue(queuedEpisode1.id)

    // Wait for queue count to be 2 (current + 1 queued)
    try await Wait.until(
      { @MainActor in
        self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int == 2
      },
      { @MainActor in
        """
        Expected queue count to be 2 after removal, got \
        \(String(describing: self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount]))
        """
      }
    )

    // Remove second episode from queue
    try await queue.dequeue(queuedEpisode2.id)

    // Wait for queue count to be 1 (current item only)
    try await Wait.until(
      { @MainActor in
        self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int == 1
      },
      { @MainActor in
        """
        Expected queue count to be 1 after all removed, got \
        \(String(describing: self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount]))
        """
      }
    )
  }

  @Test("nextTrackCommand disables when queue empties while paused")
  func nextTrackCommandDisablesWhenQueueEmptiesWhilePaused() async throws {

    await playManager.start()
    let (currentEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    try await playManager.load(currentEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Ensure initial state reflects both current and queued episodes
    try await Wait.until(
      { @MainActor in
        self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int == 2
      },
      { @MainActor in
        """
        Expected queue count to be 2, got \
        \(String(describing: self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount]))
        """
      }
    )
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == true },
      { "Expected nextTrackCommand to start enabled" }
    )

    await playManager.pause()
    try await PlayHelpers.waitFor(.paused)

    try await queue.dequeue(queuedEpisode.id)

    // Queue is empty but current episode remains paused
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == false },
      { "Expected nextTrackCommand to disable when queue becomes empty" }
    )
    try await Wait.until(
      { @MainActor in
        self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int == 1
      },
      { @MainActor in
        """
        Expected queue count to be 1 (current item only), got \
        \(String(describing: self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount]))
        """
      }
    )

    await playManager.finishEpisode(currentEpisode.id)

    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == false },
      { "Expected nextTrackCommand to stay disabled after finishing with empty queue" }
    )
    try await Wait.until(
      { @MainActor in self.nowPlayingInfo == nil },
      { @MainActor in "Expected nowPlayingInfo to clear after finishing episode" }
    )
  }

  // MARK: - Next Episode Previous Track

  @Test("nextEpisode mode previousTrack is enabled")
  func nextEpisodeModePreviousTrackIsEnabled() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)

    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.previousTrack.isEnabled == true },
      { "Expected previousTrack to be enabled in nextEpisode mode" }
    )
  }

  @Test("nextEpisode mode previousTrack seeks to zero")
  func nextEpisodeModePreviousTrackSeeksToZero() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    let duration = CMTime.seconds(240)
    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      data: (true, duration)
    )
    try await playManager.load(podcastEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    let startTime = CMTime.seconds(60)
    await playManager.seek(to: startTime)
    try await PlayHelpers.waitFor(startTime)

    mpRemoteCommandCenter.firePreviousTrack()

    try await PlayHelpers.waitFor(.zero)
    try await PlayHelpers.waitForOnDeck(podcastEpisode)
  }
}
