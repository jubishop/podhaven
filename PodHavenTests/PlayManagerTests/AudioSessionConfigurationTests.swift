// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of AudioSessionConfiguration tests", .container)
@MainActor struct AudioSessionConfigurationTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.fakeAudioSession) private var audioSession

  private var sleeper: FakeSleeper { Container.shared.sleeper() as! FakeSleeper }

  @Test("configuration succeeds on a later attempt after backing off", arguments: 1...5)
  func configurationSucceedsAfterBackoff(attempt: Int) async throws {
    audioSession.configurationErrors(
      Array(repeating: TestError.simulatedFailure, count: attempt - 1)
    )

    let configuration = Task { await PlayManager.configureAudioSession() }
    let delays = try await advanceBackoff(steps: attempt - 1)

    #expect(await configuration.value)
    #expect(delays == Array(PlayHelpers.audioSessionRetryDelays.prefix(attempt - 1)))
    #expect(audioSession.configureCallCount == attempt)
    #expect(audioSession.category == .playback)
    #expect(audioSession.mode == .spokenAudio)
    #expect(audioSession.routeSharingPolicy == .longFormAudio)
    #expect(sleeper.pendingCount() == 0)
    #expect(alert.config == nil)
  }

  @Test("configuration alerts and fails after exhausting its attempts")
  func configurationAlertsAfterExhaustingAttempts() async throws {
    PlayHelpers.failAudioSessionConfiguration()

    let configuration = Task { await PlayManager.configureAudioSession() }
    let delays = try await advanceBackoff(steps: PlayHelpers.audioSessionRetryDelays.count)

    #expect(await configuration.value == false)
    #expect(delays == PlayHelpers.audioSessionRetryDelays)
    #expect(audioSession.configureCallCount == PlayHelpers.audioSessionRetryDelays.count + 1)
    #expect(audioSession.category != .playback)
    #expect(sleeper.pendingCount() == 0)
    try await Wait.until(
      { @MainActor in alert.config?.title == "Couldn't start audio playback" },
      { @MainActor in "Expected an alert after the final configuration attempt failed" }
    )
  }

  @Test("cancellation during backoff fails without an alert or another attempt")
  func cancellationDuringBackoffFailsWithoutAlert() async throws {
    sleeper.throwsOnCancellation(true)
    PlayHelpers.failAudioSessionConfiguration()

    let configuration = Task { await PlayManager.configureAudioSession() }
    try await sleeper.waitForSleepRequests(for: PlayHelpers.audioSessionRetryDelays[0])
    configuration.cancel()

    #expect(await configuration.value == false)
    #expect(audioSession.configureCallCount == 1)
    #expect(sleeper.pendingCount() == 0)
    try await yieldForSpuriousAsyncWork()
    #expect(alert.config == nil)
  }

  private func advanceBackoff(steps: Int) async throws -> [Duration] {
    var delays: [Duration] = []
    for _ in 0..<steps {
      try await sleeper.waitForSleepRequests(count: 1)
      let pending = sleeper.pendingDurations()
      try #require(pending.count == 1)
      delays.append(pending[0])
      await sleeper.advanceTime(by: pending[0])
    }
    return delays
  }
}
