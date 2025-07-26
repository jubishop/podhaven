// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

extension TimeInterval {
  // MARK: - Conversions

  func asCMTime() -> CMTime {
    CMTime.seconds(self)
  }

  func asDuration() -> Duration {
    Duration.seconds(self)
  }

  // MARK: - Creation Helpers

  static func milliseconds(_ milliseconds: Double) -> TimeInterval {
    TimeInterval(milliseconds / 1000)
  }

  static func seconds(_ seconds: Double) -> TimeInterval {
    TimeInterval(seconds)
  }

  static func minutes(_ minutes: Double) -> TimeInterval {
    TimeInterval(minutes * 60)
  }

  // MARK: - Formatting

  var compactReadableFormat: String {
    let hours = Int(self) / 3600
    let minutes = (Int(self) % 3600) / 60
    let seconds = Int(self) % 60

    if hours > 0 {
      return "\(hours)h \(minutes)m"
    } else if minutes > 0 {
      return "\(minutes)m \(seconds)s"
    } else {
      return "\(seconds)s"
    }
  }

  var playbackTimeFormat: String {
    let totalSeconds = Int(self)
    let minutes = totalSeconds / 60
    let remainingSeconds = totalSeconds % 60
    return String(format: "%d:%02d", minutes, remainingSeconds)
  }
}
