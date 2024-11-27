// Copyright Justin Bishop, 2024

import Foundation

extension Thread {
  static func sleep(for duration: Duration) {
    let components = duration.components
    let timeInterval =
      Double(components.seconds) + Double(components.attoseconds)
      / 1_000_000_000_000_000_000
    Thread.sleep(forTimeInterval: timeInterval)
  }
}
