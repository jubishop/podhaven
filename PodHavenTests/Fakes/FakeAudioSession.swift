// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation

@testable import PodHaven

extension Container {
  var fakeAudioSession: Factory<FakeAudioSession> {
    Factory(self) { FakeAudioSession() }.scope(.cached)
  }
}

final class FakeAudioSession: AudioSessioning {
  private struct State {
    var configureCallCount = 0
    var category: AVAudioSession.Category = .soloAmbient
    var mode: AVAudioSession.Mode = .default
    var routeSharingPolicy: AVAudioSession.RouteSharingPolicy = .default
    var activeCalls: [Bool] = []
    var active = false
  }

  private let state = ThreadSafe(State())

  // Each configuration attempt throws the next scripted error; attempts succeed once none remain.
  let configurationErrors = ThreadSafe<[any Error & Sendable]>([])
  let activationError = ThreadSafe<(any Error & Sendable)?>(nil)
  let routeOutputs = ThreadSafe<[AVAudioSession.Port]>([.builtInSpeaker])

  var configureCallCount: Int { state().configureCallCount }
  var activeCalls: [Bool] { state().activeCalls }
  var active: Bool { state().active }

  var category: AVAudioSession.Category { state().category }
  var mode: AVAudioSession.Mode { state().mode }
  var routeSharingPolicy: AVAudioSession.RouteSharingPolicy { state().routeSharingPolicy }
  var isOtherAudioPlaying: Bool { false }
  var currentRouteOutputs: [AVAudioSession.Port] { routeOutputs() }

  func setCategory(
    _ category: AVAudioSession.Category,
    mode: AVAudioSession.Mode,
    policy: AVAudioSession.RouteSharingPolicy,
    options: AVAudioSession.CategoryOptions
  ) throws {
    state { $0.configureCallCount += 1 }
    let error: (any Error & Sendable)? = configurationErrors { errors in
      errors.isEmpty ? nil : errors.removeFirst()
    }
    if let error { throw error }
    state {
      $0.category = category
      $0.mode = mode
      $0.routeSharingPolicy = policy
    }
  }

  func setMode(_ mode: AVAudioSession.Mode) throws {
    state { $0.mode = mode }
  }

  func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
    if active, let error = activationError() { throw error }
    state {
      $0.activeCalls.append(active)
      $0.active = active
    }
  }
}
