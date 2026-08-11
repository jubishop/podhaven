// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of widget route-change playback recovery", .container)
@MainActor struct RouteChangeRecoveryTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.notifier) private var notifier
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager

  private var avPlayer: FakeAVPlayer {
    guard let avPlayer = Container.shared.avPlayer() as? FakeAVPlayer else {
      Assert.fatal("Expected FakeAVPlayer")
    }
    return avPlayer
  }
  private var sleeper: FakeSleeper {
    guard let sleeper = Container.shared.sleeper() as? FakeSleeper else {
      Assert.fatal("Expected FakeSleeper")
    }
    return sleeper
  }
  private var widgetState: WidgetState { Container.shared.widgetState() }

  init() {
    stateManager.start()
    cacheManager.start()
  }

  @Test("a cached widget resume recovers once after a route-change stall")
  func cachedWidgetResumeRecoversOnce() async throws {
    try await LogCapture.withSink { sink in
      _ = try await startWidgetPlayback(cached: true)
      #expect(avPlayer.playCallCount == 1)

      try await sendRouteChangeAndWaitForConsumption(sink)
      avPlayer.waitingToPlay(waitingReason: .evaluatingBufferingRate)
      try await PlayHelpers.waitFor(.waiting)
      try await waitForWidgetStatus(.waiting)

      avPlayer.pause()
      try await PlayHelpers.waitFor(.paused)
      try await sleeper.waitForSleepRequests(for: .seconds(1))
      await sleeper.advanceTime(by: .seconds(1))

      try await PlayHelpers.waitFor(.playing)
      try await waitForWidgetStatus(.playing)
      avPlayer.advanceTime(to: .seconds(1))
      try await PlayHelpers.waitFor(.seconds(1))
      #expect(avPlayer.playCallCount == 2)

      avPlayer.waitingToPlay(waitingReason: .evaluatingBufferingRate)
      try await PlayHelpers.waitFor(.waiting)
      avPlayer.pause()
      try await PlayHelpers.waitFor(.paused)
      await sleeper.advanceTime(by: .seconds(20))
      await Task.yield()

      #expect(avPlayer.playCallCount == 2)
      try await Wait.until(
        {
          sink.captured()
            .contains {
              $0.message.contains("event=widgetRouteRecoverySucceeded")
            }
        },
        { "Expected a successful route recovery diagnostic" }
      )
      let captured = sink.captured()
      #expect(
        captured.contains {
          $0.message.contains("event=playPauseIntent requestedPlaying=true")
            && $0.message.contains("appState=")
        }
      )
      #expect(
        captured.contains {
          $0.message.contains("event=playRequest")
            && $0.message.contains("origin=widget")
            && $0.message.contains("playerGeneration=")
            && $0.message.contains("itemStatus=")
            && $0.message.contains("cached=true")
            && $0.message.contains("routeOutputs=")
        }
      )
      #expect(
        captured.contains {
          $0.message.contains("event=playerTimeControlStatus")
            && $0.message.contains("status=waiting")
            && $0.message.contains("waitingReason=")
        }
      )
      #expect(
        captured.count {
          $0.message.contains("event=widgetRouteRecoveryAttempt")
        } == 1
      )
    }
  }

  @Test("a newer user pause cancels scheduled route recovery")
  func newerPauseCancelsRecovery() async throws {
    try await LogCapture.withSink { sink in
      _ = try await startWidgetPlayback(cached: true)
      try await sendRouteChangeAndWaitForConsumption(sink)
      avPlayer.waitingToPlay(waitingReason: .evaluatingBufferingRate)
      try await PlayHelpers.waitFor(.waiting)
      avPlayer.pause()
      try await PlayHelpers.waitFor(.paused)
      try await sleeper.waitForSleepRequests(for: .seconds(1))

      await playManager.pause()
      await sleeper.advanceTime(by: .seconds(1))
      await Task.yield()

      #expect(avPlayer.playCallCount == 1)
      #expect(sharedState.playbackStatus == .paused)
      try await Wait.until(
        {
          sink.captured()
            .contains {
              $0.message.contains("event=widgetRouteRecoveryCancelled reason=userPause")
            }
        },
        { "Expected the newer pause to cancel route recovery" }
      )
    }
  }

  @Test("a replacement load cancels recovery owned by the retired player")
  func replacementLoadCancelsRecovery() async throws {
    try await LogCapture.withSink { sink in
      _ = try await startWidgetPlayback(cached: true)
      try await sendRouteChangeAndWaitForConsumption(sink)
      avPlayer.waitingToPlay(waitingReason: .evaluatingBufferingRate)
      try await PlayHelpers.waitFor(.waiting)
      avPlayer.pause()
      try await PlayHelpers.waitFor(.paused)
      try await sleeper.waitForSleepRequests(for: .seconds(1))

      let replacement = try await Create.podcastEpisode()
      #expect(try await playManager.load(replacement))
      await sleeper.advanceTime(by: .seconds(1))
      await Task.yield()

      #expect(sharedState.onDeck?.id == replacement.id)
      #expect(avPlayer.playCallCount == 1)
      try await Wait.until(
        {
          sink.captured()
            .contains {
              $0.message.contains("event=widgetRouteRecoveryCancelled reason=newLoad")
            }
        },
        { "Expected the replacement load to cancel route recovery" }
      )
    }
  }

  @Test("remote buffering without a route change does not recover")
  func remoteBufferingWithoutRouteChangeDoesNotRecover() async throws {
    try await LogCapture.withSink { sink in
      _ = try await startWidgetPlayback(cached: false)
      avPlayer.waitingToPlay(waitingReason: .evaluatingBufferingRate)
      try await PlayHelpers.waitFor(.waiting)
      avPlayer.pause()
      try await PlayHelpers.waitFor(.paused)

      try await Wait.until(
        {
          sink.captured()
            .contains {
              $0.message.contains("event=widgetRouteRecoverySkipped")
                && $0.message.contains("reason=noRouteChange")
            }
        },
        { "Expected ordinary buffering to be excluded from route recovery" }
      )
      await sleeper.advanceTime(by: .seconds(20))
      await Task.yield()

      #expect(avPlayer.playCallCount == 1)
      #expect(sharedState.playbackStatus == .paused)
    }
  }

  @Test("an unsuccessful recovery becomes stably paused after one timeout")
  func unsuccessfulRecoveryBecomesPaused() async throws {
    try await LogCapture.withSink { sink in
      avPlayer.queuePlayStatuses([.playing, .waitingToPlayAtSpecifiedRate])
      _ = try await startWidgetPlayback(cached: true)
      try await sendRouteChangeAndWaitForConsumption(sink)
      avPlayer.waitingToPlay(waitingReason: .evaluatingBufferingRate)
      try await PlayHelpers.waitFor(.waiting)
      avPlayer.pause()
      try await PlayHelpers.waitFor(.paused)
      try await sleeper.waitForSleepRequests(for: .seconds(1))

      await sleeper.advanceTime(by: .seconds(1))
      try await PlayHelpers.waitFor(.waiting)
      try await sleeper.waitForSleepRequests(for: .seconds(10))
      await sleeper.advanceTime(by: .seconds(10))

      try await PlayHelpers.waitFor(.paused)
      try await waitForWidgetStatus(.paused)
      #expect(avPlayer.playCallCount == 2)
      try await Wait.until(
        {
          sink.captured()
            .contains {
              $0.message.contains("event=widgetRouteRecoveryFailed reason=timeout")
            }
        },
        { "Expected the bounded recovery timeout diagnostic" }
      )
    }
  }

  private func startWidgetPlayback(cached: Bool) async throws -> PodcastEpisode {
    let unsavedEpisode =
      try cached
      ? Create.unsavedEpisode(cachedFilename: "widget-route-recovery.mp3")
      : Create.unsavedEpisode()
    let podcastEpisode = try await Create.podcastEpisode(unsavedEpisode)
    #expect(try await playManager.load(podcastEpisode))

    let result = try await PlayPauseIntent(playing: true).perform()
    withExtendedLifetime(result) {}
    try await PlayHelpers.waitFor(.playing)
    try await waitForWidgetStatus(.playing)
    return podcastEpisode
  }

  private func sendRouteChangeAndWaitForConsumption(_ sink: LogCapture.Sink) async throws {
    notifier.continuation(for: AVAudioSession.routeChangeNotification)
      .yield(
        Notification(
          name: AVAudioSession.routeChangeNotification,
          userInfo: [
            AVAudioSessionRouteChangeReasonKey:
              AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
          ]
        )
      )
    try await Wait.until(
      {
        sink.captured()
          .contains {
            $0.label == "Play/manager" && $0.message.contains("Audio route changed")
          }
      },
      { "Expected the route-change notification to be consumed" }
    )
  }

  private func waitForWidgetStatus(_ status: PlaybackStatus) async throws {
    try await Wait.until(
      { @MainActor in widgetState.playbackStatus == status },
      { @MainActor in "Expected widget status \(status), got \(widgetState.playbackStatus)" }
    )
  }
}
