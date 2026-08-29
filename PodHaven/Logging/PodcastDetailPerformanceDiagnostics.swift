// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import os

extension Container {
  var podcastDetailPerformanceDiagnostics: Factory<PodcastDetailPerformanceDiagnostics> {
    Factory(self) { PodcastDetailPerformanceDiagnostics() }.scope(.cached)
  }
}

struct PodcastDetailPerformanceDiagnostics: Sendable {
  enum Phase: String, Sendable {
    case stateComparison
    case stateTransition
    case episodeProjection
    case filterRefresh

    fileprivate var warningThreshold: Duration {
      switch self {
      case .stateComparison: .milliseconds(100)
      case .stateTransition, .episodeProjection, .filterRefresh: .milliseconds(250)
      }
    }
  }

  private struct Sample: Sendable {
    let sequence: Int
    let phase: Phase
    let duration: Duration
    let episodeCount: Int
    let mainThread: Bool
    let thermalPressure: ThermalPressure
    let scenePhase: String
  }

  private struct Storage: Sendable {
    var nextSequence = 1
    var samples: [Sample] = []
  }

  @DynamicInjected(\.continuousClockNow) private var continuousClockNow
  @DynamicInjected(\.sharedState) private var sharedState

  private static let log = Log.as(LogSubsystem.PodcastsView.detail)
  private static let sampleCapacity = 32
  private static let signposter = OSSignposter(
    subsystem: AppInfo.bundleIdentifier,
    category: "PodcastDetailPerformance"
  )

  private let storage = ThreadSafe(Storage())

  fileprivate init() {}

  @concurrent func statesEqual(
    _ lhs: PodcastDetailState,
    _ rhs: PodcastDetailState
  ) async -> Bool {
    let startedAt = continuousClockNow()
    let signpostState = Self.signposter.beginInterval("StateComparison")
    let equal = lhs == rhs
    Self.signposter.endInterval("StateComparison", signpostState)
    record(
      phase: .stateComparison,
      startedAt: startedAt,
      episodeCount: max(lhs.episodeCount, rhs.episodeCount),
      mainThread: Self.currentThreadIsMain
    )
    return equal
  }

  @discardableResult
  func measure<Result>(
    _ phase: Phase,
    episodeCount: Int,
    operation: () throws -> Result
  ) rethrows -> Result {
    let startedAt = continuousClockNow()
    let signpostName: StaticString =
      switch phase {
      case .stateComparison: "StateComparison"
      case .stateTransition: "StateTransition"
      case .episodeProjection: "EpisodeProjection"
      case .filterRefresh: "FilterRefresh"
      }
    let signpostState = Self.signposter.beginInterval(signpostName)
    defer {
      Self.signposter.endInterval(signpostName, signpostState)
      record(
        phase: phase,
        startedAt: startedAt,
        episodeCount: episodeCount,
        mainThread: Thread.isMainThread
      )
    }
    return try operation()
  }

  func sentryContext() -> [String: Any] {
    let samples = storage().samples
    return [
      "capacity": Self.sampleCapacity,
      "samples": samples.map { sample in
        [
          "sequence": sample.sequence,
          "phase": sample.phase.rawValue,
          "durationMs": sample.duration.asTimeInterval * 1_000,
          "episodeCount": sample.episodeCount,
          "mainThread": sample.mainThread,
          "thermalPressure": sample.thermalPressure.rawValue,
          "scenePhase": sample.scenePhase,
        ] as [String: Any]
      },
    ]
  }

  private func record(
    phase: Phase,
    startedAt: ContinuousClock.Instant,
    episodeCount: Int,
    mainThread: Bool
  ) {
    let duration = continuousClockNow() - startedAt
    let thermalPressure = sharedState.thermalPressure
    let scenePhase = String(describing: sharedState.scenePhase)
    let sample = storage { storage in
      let sample = Sample(
        sequence: storage.nextSequence,
        phase: phase,
        duration: duration,
        episodeCount: episodeCount,
        mainThread: mainThread,
        thermalPressure: thermalPressure,
        scenePhase: scenePhase
      )
      storage.nextSequence += 1
      storage.samples.append(sample)
      if storage.samples.count > Self.sampleCapacity {
        storage.samples.removeFirst(storage.samples.count - Self.sampleCapacity)
      }
      return sample
    }
    guard duration >= phase.warningThreshold else { return }
    Self.log.warning(
      "podcastDetailPerf phase=\(phase.rawValue) durationMs=\(duration.asTimeInterval * 1_000) episodeCount=\(episodeCount) mainThread=\(mainThread) sequence=\(sample.sequence) thermalPressure=\(thermalPressure.rawValue) scenePhase=\(scenePhase)"
    )
  }
  private static var currentThreadIsMain: Bool { Thread.isMainThread }
}
