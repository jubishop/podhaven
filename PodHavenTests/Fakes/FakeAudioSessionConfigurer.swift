// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

@testable import PodHaven

extension Container {
  var fakeAudioSessionConfigurer: Factory<FakeAudioSessionConfigurer> {
    Factory(self) { FakeAudioSessionConfigurer() }.scope(.cached)
  }
}

actor FakeAudioSessionConfigurer {
  private(set) var callCount = 0
  func configure() throws { callCount += 1 }
}
