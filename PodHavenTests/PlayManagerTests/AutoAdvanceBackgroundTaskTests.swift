// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing
import UIKit

@testable import PodHaven

@Suite("of automatic advancement background task tests", .container)
@MainActor struct AutoAdvanceBackgroundTaskTests {
  enum Exit: CaseIterable { case stopAfterCurrentEpisode, noReplacement, loadFailure }
  enum NewerRequest: CaseIterable { case pause, stop, load, play }

  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager
  @DynamicInjected(\.uiApplication) private var uiApplication
  @DynamicInjected(\.userSettings) private var userSettings

  private var application: FakeApplication { uiApplication as! FakeApplication }
  private var avPlayer: FakeAVPlayer { Container.shared.avPlayer() as! FakeAVPlayer }

  private nonisolated static let taskName = "autoAdvance"

  init() async throws {
    stateManager.start()
  }

  @Test("automatic advancement holds one background task until the remote next episode plays")
  func holdsTaskUntilNextEpisodePlays() async throws {
    let (currentEpisode, nextEpisode) = try await Create.twoPodcastEpisodes()
    let fakeRepo = try #require(repo as? FakeRepo)
    try await queue.unshift(nextEpisode.id)
    try await startPlaying(currentEpisode)

    let heldWhileMarking = ThreadSafe<[UIBackgroundTaskIdentifier]?>(nil)
    await fakeRepo.afterNextMarkFinished { @MainActor [application] _ in
      heldWhileMarking(
        application.taskIdentifiers(named: Self.taskName).filter(application.hasActiveTask)
      )
    }
    let finishLoading = await episodeAssetLoader.waitRespond(to: nextEpisode.episode.mediaURL)
    avPlayer.queuePlayStatuses([.waitingToPlayAtSpecifiedRate])
    avPlayer.finishEpisode()

    try await PlayHelpers.waitFor(.loading(nextEpisode.episode.title))
    let identifier = try autoAdvanceTask()
    #expect(heldWhileMarking() == [identifier])
    #expect(application.hasActiveTask(identifier: identifier))

    finishLoading.signal()
    try await PlayHelpers.waitFor(.waiting)
    #expect(application.hasActiveTask(identifier: identifier))

    avPlayer.resumePlayback()
    try await PlayHelpers.waitFor(.playing)
    try await waitForEnd(of: identifier)
    #expect(application.taskIdentifiers(named: Self.taskName) == [identifier])
  }

  @Test(
    "automatic advancement ends its background task when it stops without playback",
    arguments: Exit.allCases
  )
  func endsTaskWithoutPlayback(exit: Exit) async throws {
    let (currentEpisode, nextEpisode) = try await Create.twoPodcastEpisodes()
    try await startPlaying(currentEpisode)
    switch exit {
    case .stopAfterCurrentEpisode:
      try await queue.unshift(nextEpisode.id)
      sharedState.setStopAfterCurrentEpisode(true)
    case .noReplacement:
      userSettings.$autoPlayTopRecommendationWhenQueueEmpty.new(false)
    case .loadFailure:
      try await queue.unshift(nextEpisode.id)
      await episodeAssetLoader.respond(
        to: nextEpisode.episode.mediaURL,
        error: TestError.assetLoadFailure(nextEpisode)
      )
    }

    avPlayer.finishEpisode()

    try await PlayHelpers.waitFor(.stopped)
    try await waitForEnd(of: try autoAdvanceTask())
  }

  @Test("a newer load during automatic loading ends the background task")
  func newerLoadDuringAutomaticLoadEndsTask() async throws {
    let (currentEpisode, nextEpisode, selectedEpisode) = try await Create.threePodcastEpisodes()
    try await queue.unshift(nextEpisode.id)
    try await startPlaying(currentEpisode)
    let finishLoading = await episodeAssetLoader.waitRespond(to: nextEpisode.episode.mediaURL)
    defer { finishLoading.signal() }

    avPlayer.finishEpisode()
    try await PlayHelpers.waitFor(.loading(nextEpisode.episode.title))
    let identifier = try autoAdvanceTask()

    try await playManager.load(selectedEpisode)

    try await PlayHelpers.waitForOnDeck(selectedEpisode)
    try await waitForEnd(of: identifier)
    #expect(application.taskIdentifiers(named: Self.taskName) == [identifier])
  }

  @Test(
    "a newer request while the next episode buffers ends the background task",
    arguments: NewerRequest.allCases
  )
  func newerRequestWhileBufferingEndsTask(request: NewerRequest) async throws {
    let (currentEpisode, nextEpisode, selectedEpisode) = try await Create.threePodcastEpisodes()
    try await queue.unshift(nextEpisode.id)
    try await startPlaying(currentEpisode)
    avPlayer.queuePlayStatuses([.waitingToPlayAtSpecifiedRate])

    avPlayer.finishEpisode()
    try await PlayHelpers.waitForOnDeck(nextEpisode)
    try await PlayHelpers.waitFor(.waiting)
    let identifier = try autoAdvanceTask()
    #expect(application.hasActiveTask(identifier: identifier))

    switch request {
    case .pause: await playManager.pause()
    case .stop: await playManager.stop()
    case .load: try await playManager.load(selectedEpisode)
    case .play: try await playManager.play(selectedEpisode)
    }

    try await waitForEnd(of: identifier)
    #expect(application.taskIdentifiers(named: Self.taskName) == [identifier])
  }

  @Test("a newer automatic advancement replaces the background task of one still buffering")
  func newerAdvancementReplacesBufferingTask() async throws {
    let (currentEpisode, nextEpisode) = try await Create.twoPodcastEpisodes()
    userSettings.$autoPlayTopRecommendationWhenQueueEmpty.new(false)
    try await queue.unshift(nextEpisode.id)
    try await startPlaying(currentEpisode)
    avPlayer.queuePlayStatuses([.waitingToPlayAtSpecifiedRate])

    avPlayer.finishEpisode()
    try await PlayHelpers.waitForOnDeck(nextEpisode)
    try await PlayHelpers.waitFor(.waiting)
    let buffering = try autoAdvanceTask()

    await playManager.finishEpisode()

    let identifiers = application.taskIdentifiers(named: Self.taskName)
    try #require(identifiers.count == 2)
    #expect(identifiers[0] == buffering)
    try await waitForEnd(of: identifiers[0])
    try await waitForEnd(of: identifiers[1])
    #expect(sharedState.playbackStatus == .stopped)
  }

  @Test("expiration before playback logs the phase and ends the background task once")
  func expirationBeforePlaybackLogsPhaseAndEndsOnce() async throws {
    let (currentEpisode, nextEpisode) = try await Create.twoPodcastEpisodes()
    try await queue.unshift(nextEpisode.id)

    try await LogCapture.withSink { sink in
      try await startPlaying(currentEpisode)
      let finishLoading = await episodeAssetLoader.waitRespond(to: nextEpisode.episode.mediaURL)

      avPlayer.finishEpisode()
      try await PlayHelpers.waitFor(.loading(nextEpisode.episode.title))
      let identifier = try autoAdvanceTask()

      application.expireTask(identifier)

      let warnings = sink.captured()
        .filter { $0.level == .warning && $0.message.contains("event=autoAdvanceExpired") }
        .map(\.message)
      try #require(warnings.count == 1)
      #expect(warnings[0].contains("phase=loading(\(nextEpisode.id))"))
      #expect(warnings[0].contains("elapsedSeconds="))
      #expect(!application.hasActiveTask(identifier: identifier))
      #expect(application.endCallCount(for: identifier) == 1)

      finishLoading.signal()
      try await PlayHelpers.waitFor(.playing)
      try await Wait.until(
        { sink.captured().contains { $0.message == "end: \(Self.taskName) id invalid in end" } },
        { "Expected playback to settle the expired background task" }
      )
      #expect(application.endCallCount(for: identifier) == 1)
    }
  }

  // MARK: - Helpers

  private func startPlaying(_ podcastEpisode: PodcastEpisode) async throws {
    PlayHelpers.setupCommandHandling()
    await playManager.start()
    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()
  }

  private func autoAdvanceTask() throws -> UIBackgroundTaskIdentifier {
    let identifiers = application.taskIdentifiers(named: Self.taskName)
    try #require(identifiers.count == 1, "Expected one \(Self.taskName) task, got \(identifiers)")
    return identifiers[0]
  }

  private func waitForEnd(of identifier: UIBackgroundTaskIdentifier) async throws {
    try await Wait.until(
      { @MainActor in !application.hasActiveTask(identifier: identifier) },
      { @MainActor in "Expected \(Self.taskName) background task \(identifier) to end" }
    )
    #expect(application.endCallCount(for: identifier) == 1)
  }
}
