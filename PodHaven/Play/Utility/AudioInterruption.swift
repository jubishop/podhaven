// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import Logging

enum AudioInterruption {
  private static let log = Log.as("AudioInterruption")

  case began
  case ended(shouldResume: Bool)
  case ignore

  static func parse(_ notification: Notification) -> AudioInterruption {
    guard notification.name == AVAudioSession.interruptionNotification,
      let userInfo = notification.userInfo,
      let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else {
      log.warning("Ignoring invalid interruption notification: \(notification)")
      return .ignore
    }

    switch type {
    case .began:
      return .began
    case .ended:
      guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
        log.warning("Ignoring interruption end without options: \(userInfo)")
        return .ignore
      }

      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      return .ended(shouldResume: options.contains(.shouldResume))
    @unknown default:
      log.warning("Unknown notification type: \(type)")
      return .ignore
    }
  }
}
