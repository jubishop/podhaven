// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

extension TimeInterval {
  // MARK: - Conversions

  var asCMTime: CMTime { CMTime.seconds(self) }
  var asDuration: Duration { Duration.seconds(self) }

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

  static func hours(_ hours: Double) -> TimeInterval {
    TimeInterval(hours * 3600)
  }

  static func days(_ days: Double) -> TimeInterval {
    TimeInterval(days * 86400)
  }

  // MARK: - Formatting

  var compactReadableFormat: String {
    let (hours, minutes, seconds) = formattedParts

    return negate(
      hours != 0
        ? "\(hours)h \(minutes)m"
        : minutes != 0
          ? "\(minutes)m \(seconds)s"
          : "\(seconds)s"
    )
  }

  var playbackTimeFormat: String {
    let (hours, minutes, seconds) = formattedParts

    return negate(
      hours != 0
        ? "\(hours):\(minutes.zeroPadded(to: 2)):\(seconds.zeroPadded(to: 2))"
        : "\(minutes):\(seconds.zeroPadded(to: 2))"
    )
  }

  private func negate(_ formattedString: String) -> String {
    self < 0 ? "-\(formattedString)" : formattedString
  }

  private var formattedParts: (Int, Int, Int) {
    let hours = abs(Int(self) / 3600)
    let minutes = abs((Int(self) % 3600) / 60)
    let seconds = abs(Int(self) % 60)

    return (hours, minutes, seconds)
  }
}
