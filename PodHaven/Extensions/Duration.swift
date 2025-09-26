// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

extension Duration {
  // MARK: - Conversions

  var asCMTime: CMTime { CMTime.seconds(self / .seconds(1)) }
  var asTimeInterval: TimeInterval { TimeInterval.seconds(self / .seconds(1)) }

  // MARK: - Creation Helpers

  static func milliseconds(_ milliseconds: Double) -> Duration {
    seconds(milliseconds / 1000)
  }

  static func minutes(_ minutes: Double) -> Duration {
    seconds(minutes * 60)
  }

  static func hours(_ hours: Double) -> Duration {
    seconds(hours * 3600)
  }
}
