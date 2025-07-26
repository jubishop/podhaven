// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

extension Duration {
  // MARK: - Conversions

  func asCMTime() -> CMTime {
    CMTime.seconds(self / .seconds(1))
  }

  func asTimeInterval() -> TimeInterval {
    TimeInterval.seconds(self / .seconds(1))
  }

  // MARK: - Creation Helpers

  static func minutes(_ minutes: Double) -> Duration {
    seconds(minutes * 60)
  }
}
