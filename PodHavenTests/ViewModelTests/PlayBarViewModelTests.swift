// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of PlayBarViewModel tests", .container)
@MainActor final class PlayBarViewModelTests {
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager

  private var viewModel = PlayBarViewModel()

  private func episodeOnDeck(currentTime: CMTime = .zero) async throws -> PodcastEpisode {
    let podcastEpisode = try await Create.podcastEpisode(
      try Create.unsavedEpisode(currentTime: currentTime)
    )
    stateManager.setOnDeck(podcastEpisode)
    return podcastEpisode
  }

  // MARK: - maxPlaybackTime

  @Test("maxPlaybackTime is zero when no episode is on deck")
  func maxPlaybackTimeZeroWithoutOnDeck() {
    #expect(sharedState.onDeck == nil)
    #expect(viewModel.maxPlaybackTime == 0)
  }

  @Test("maxPlaybackTime grows with forward playback and holds after seek-back")
  func maxPlaybackTimeTracksPeak() async throws {
    _ = try await episodeOnDeck()
    #expect(viewModel.maxPlaybackTime == 0)

    stateManager.setCurrentTime(CMTime.seconds(200))
    #expect(viewModel.maxPlaybackTime == 200)

    // Seek back — the in-memory peak stays.
    stateManager.setCurrentTime(CMTime.seconds(50))
    #expect(viewModel.maxPlaybackTime == 200)
  }

  @Test("maxPlaybackTime falls back to the scrubber when onDeck peak trails it")
  func maxPlaybackTimeFallsBackToSlider() async throws {
    _ = try await episodeOnDeck()
    // Simulate the race where currentTime just moved but the in-memory peak
    // hasn't caught up — the VM should never appear "behind" the scrubber.
    sharedState.$onDeck.update { onDeck in
      onDeck?.currentTime = CMTime.seconds(42)
      onDeck?.maxPlaybackTime = CMTime.seconds(10)
    }

    #expect(viewModel.sliderValue == 42)
    #expect(viewModel.maxPlaybackTime == 42)
  }

  @Test("maxPlaybackTime is hydrated from the DB when setOnDeck fires")
  func maxPlaybackTimeHydratedFromDB() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      try Create.unsavedEpisode()
    )

    // Persist a peak via the repo path (which also advances currentTime).
    try await repo.updateCurrentTime(podcastEpisode.id, currentTime: CMTime.seconds(180))
    let refreshed = try #require(try await repo.podcastEpisode(podcastEpisode.id))
    stateManager.setOnDeck(refreshed)

    #expect(sharedState.onDeck?.maxPlaybackTime == CMTime.seconds(180))
    #expect(viewModel.maxPlaybackTime == 180)
  }

  // MARK: - canJumpToMaxPlayback

  @Test("canJumpToMaxPlayback is false when there is no episode on deck")
  func canJumpFalseWithoutOnDeck() {
    #expect(sharedState.onDeck == nil)
    #expect(viewModel.canJumpToMaxPlayback == false)
  }

  @Test("canJumpToMaxPlayback is false when the scrubber sits at the peak")
  func canJumpFalseAtPeak() async throws {
    _ = try await episodeOnDeck()
    stateManager.setCurrentTime(CMTime.seconds(120))

    #expect(viewModel.sliderValue == 120)
    #expect(viewModel.maxPlaybackTime == 120)
    #expect(viewModel.canJumpToMaxPlayback == false)
  }

  @Test("canJumpToMaxPlayback is false when the gap is within the 20s threshold")
  func canJumpFalseBelowThreshold() async throws {
    _ = try await episodeOnDeck()

    stateManager.setCurrentTime(CMTime.seconds(200))
    // Seek back by exactly 20s — boundary condition, should not jump.
    stateManager.setCurrentTime(CMTime.seconds(180))
    #expect(viewModel.canJumpToMaxPlayback == false)

    // Seek back a little more but still under the threshold.
    stateManager.setCurrentTime(CMTime.seconds(185))
    #expect(viewModel.canJumpToMaxPlayback == false)
  }

  @Test("canJumpToMaxPlayback is true when the peak is more than 20s ahead")
  func canJumpTrueAboveThreshold() async throws {
    _ = try await episodeOnDeck()

    stateManager.setCurrentTime(CMTime.seconds(300))
    stateManager.setCurrentTime(CMTime.seconds(100))

    #expect(viewModel.canJumpToMaxPlayback == true)
    #expect(viewModel.maxPlaybackTime == 300)
  }
}
