// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

@testable import PodHaven

extension Container {
  var fakeAudioSession: Factory<FakeAudioSession> {
    Factory(self) { FakeAudioSession() }.scope(.cached)
  }
}

actor FakeAudioSession {
  private(set) var configureCallCount = 0
  func configure() throws { configureCallCount += 1 }

  private(set) var activeCalls: [Bool] = []
  private(set) var active: Bool = false
  func setActive(_ active: Bool) throws {
    activeCalls.append(active)
    self.active = active
  }
}
