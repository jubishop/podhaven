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

  @Test("a cached widget resume recovers while buffer evaluation remains waiting")
  func cachedWidgetResumeRecoversWhileWaiting() async throws {
    try await LogCapture.withSink { sink in
      try await startWidgetPlayback(cached: true)
      try await sendRouteChangeAndWaitForConsumption(sink)
      avPlayer.waitingToPlay(waitingReason: .evaluatingBufferingRate)
      try await PlayHelpers.waitFor(.waiting)
      try await waitForWidgetStatus(.waiting)

      try await sleeper.waitForSleepRequests(for: .seconds(1))
      await sleeper.advanceTime(by: .seconds(1))

      try await PlayHelpers.waitFor(.playing)
      try await waitForWidgetStatus(.playing)
      #expect(avPlayer.playCallCount == 2)
      try await Wait.until(
        {
          sink.captured()
            .count {
              $0.message.contains("event=widgetRouteRecoveryAttempt")
            } == 1
        },
        { "Expected one recovery attempt while AVPlayer remained waiting" }
      )
    }
  }

  @Test("progress before the waiting deadline cancels route recovery")
  func progressBeforeWaitingDeadlineCancelsRecovery() async throws {
    try await LogCapture.withSink { sink in
      try await startWidgetPlayback(cached: true)
      try await sendRouteChangeAndWaitForConsumption(sink)
      avPlayer.waitingToPlay(waitingReason: .evaluatingBufferingRate)
      try await PlayHelpers.waitFor(.waiting)
      try await sleeper.waitForSleepRequests(for: .seconds(1))

      avPlayer.advanceTime(to: .seconds(1))
      try await PlayHelpers.waitFor(.seconds(1))
      await sleeper.advanceTime(by: .seconds(1))
      await Task.yield()

      #expect(avPlayer.playCallCount == 1)
      try await Wait.until(
        {
          sink.captured()
            .contains {
              $0.message.contains("event=widgetRouteRecoveryCancelled reason=timeAdvanced")
            }
        },
        { "Expected progress to cancel the waiting recovery deadline" }
      )
    }
  }

  @Test("a cached widget resume recovers once after a route-change stall")
  func cachedWidgetResumeRecoversOnce() async throws {
    try await LogCapture.withSink { sink in
      try await startWidgetPlayback(cached: true)
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

  @Test("late route churn does not postpone an already scheduled retry")
  func lateRouteChurnDoesNotPostponeRetry() async throws {
    try await LogCapture.withSink { sink in
      let requestedAt = Date(timeIntervalSince1970: 1_000)
      let associationWindow = await playManager.routeChangeAssociationWindow
      Container.shared.fakeDate().freeze(at: requestedAt)
      try await startWidgetPlayback(cached: true)

      try await sendRouteChangeAndWaitForConsumption(sink)
      avPlayer.waitingToPlay(waitingReason: .evaluatingBufferingRate)
      try await PlayHelpers.waitFor(.waiting)
      avPlayer.pause()
      try await PlayHelpers.waitFor(.paused)
      try await sleeper.waitForSleepRequests(for: .seconds(1))

      await sleeper.advanceTime(by: .milliseconds(500))
      Container.shared.fakeDate()
        .freeze(
          at: requestedAt.addingTimeInterval(associationWindow + 1)
        )
      await playManager.recordAudioRouteChange(
        reason: .newDeviceAvailable,
        previousOutputs: [],
        currentOutputs: []
      )
      await sleeper.advanceTime(by: .milliseconds(500))

      try await PlayHelpers.waitFor(.playing)
      #expect(avPlayer.playCallCount == 2)
    }
  }

  @Test("a newer user pause cancels scheduled route recovery")
  func newerPauseCancelsRecovery() async throws {
    try await LogCapture.withSink { sink in
      try await startWidgetPlayback(cached: true)
      try await sendRouteChangeAndWaitForConsumption(sink)
      avPlayer.waitingToPlay(waitingReason: .evaluatingBufferingRate)
      try await PlayHelpers.waitFor(.waiting)
      try await sleeper.waitForSleepRequests(for: .seconds(1))

      await playManager.pause()
      try await PlayHelpers.waitFor(.paused)
      try await waitForWidgetStatus(.paused)
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

  @Test("a newer user play cancels waiting route recovery")
  func newerPlayCancelsRecovery() async throws {
    try await LogCapture.withSink { sink in
      try await startWidgetPlayback(cached: true)
      try await sendRouteChangeAndWaitForConsumption(sink)
      avPlayer.waitingToPlay(waitingReason: .evaluatingBufferingRate)
      try await PlayHelpers.waitFor(.waiting)
      try await sleeper.waitForSleepRequests(for: .seconds(1))

      await playManager.play()
      try await PlayHelpers.waitFor(.playing)
      await sleeper.advanceTime(by: .seconds(1))
      await Task.yield()

      #expect(avPlayer.playCallCount == 2)
      try await Wait.until(
        {
          sink.captured()
            .contains {
              $0.message.contains("event=widgetRouteRecoveryCancelled reason=newPlay")
            }
        },
        { "Expected the newer play to cancel route recovery" }
      )
    }
  }

  @Test("a replacement load cancels recovery owned by the retired player")
  func replacementLoadCancelsRecovery() async throws {
    try await LogCapture.withSink { sink in
      try await startWidgetPlayback(cached: true)
      try await sendRouteChangeAndWaitForConsumption(sink)
      avPlayer.waitingToPlay(waitingReason: .evaluatingBufferingRate)
      try await PlayHelpers.waitFor(.waiting)
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

  @Test("a new player generation cancels recovery owned by the retired player")
  func sameEpisodeReloadCancelsRecovery() async throws {
    try await LogCapture.withSink { sink in
      let episode = try await startWidgetPlayback(cached: true)
      try await sendRouteChangeAndWaitForConsumption(sink)
      avPlayer.waitingToPlay(waitingReason: .evaluatingBufferingRate)
      try await PlayHelpers.waitFor(.waiting)
      try await sleeper.waitForSleepRequests(for: .seconds(1))

      let reloadedEpisode = try await Container.shared.podAVPlayer().load(episode)
      withExtendedLifetime(reloadedEpisode) {}
      await sleeper.advanceTime(by: .seconds(1))

      #expect(sharedState.onDeck?.id == episode.id)
      #expect(avPlayer.playCallCount == 1)
      try await Wait.until(
        {
          sink.captured()
            .contains {
              $0.message.contains(
                "event=widgetRouteRecoveryCancelled reason=retryOwnershipChanged"
              )
            }
        },
        { "Expected the player replacement to cancel route recovery" }
      )
    }
  }

  @Test("remote buffering without a route change does not recover")
  func remoteBufferingWithoutRouteChangeDoesNotRecover() async throws {
    try await LogCapture.withSink { sink in
      try await startWidgetPlayback(cached: false)
      avPlayer.waitingToPlay(waitingReason: .evaluatingBufferingRate)
      try await PlayHelpers.waitFor(.waiting)
      await sleeper.advanceTime(by: .seconds(20))
      await Task.yield()

      #expect(avPlayer.playCallCount == 1)
      #expect(sharedState.playbackStatus == .waiting)
      #expect(
        !sink.captured()
          .contains {
            $0.message.contains("event=widgetRouteRecoveryAttempt")
          }
      )
    }
  }

  @Test("an unsuccessful recovery becomes stably paused after one timeout")
  func unsuccessfulRecoveryBecomesPaused() async throws {
    try await LogCapture.withSink { sink in
      avPlayer.queuePlayStatuses([.playing, .waitingToPlayAtSpecifiedRate])
      try await startWidgetPlayback(cached: true)
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

  @Test("transient playing without progress still times out")
  func transientPlayingWithoutProgressTimesOut() async throws {
    try await LogCapture.withSink { sink in
      avPlayer.queuePlayStatuses([.playing, .playing])
      try await startWidgetPlayback(cached: true)
      try await sendRouteChangeAndWaitForConsumption(sink)
      avPlayer.waitingToPlay(waitingReason: .evaluatingBufferingRate)
      try await PlayHelpers.waitFor(.waiting)
      avPlayer.pause()
      try await PlayHelpers.waitFor(.paused)
      try await sleeper.waitForSleepRequests(for: .seconds(1))

      await sleeper.advanceTime(by: .seconds(1))
      try await PlayHelpers.waitFor(.playing)
      avPlayer.waitingToPlay(waitingReason: .evaluatingBufferingRate)
      try await PlayHelpers.waitFor(.waiting)

      try #require(await playManager.widgetRouteRecovery != nil)
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
        { "Expected transient playing without progress to reach the recovery timeout" }
      )
    }
  }

  @discardableResult
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
