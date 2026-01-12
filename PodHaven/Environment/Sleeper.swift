// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

extension Container {
  var sleeper: Factory<any Sleepable> {
    self { Sleeper() }.cached
  }
}

struct Sleeper: Sleepable {
  func sleep(for duration: Duration) async throws {
    try await Task.sleep(for: duration)
  }
}
