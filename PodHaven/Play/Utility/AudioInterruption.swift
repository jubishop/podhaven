// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

enum AudioInterruption {
  case pause, resume, ignore

  static func parse(_ notification: Notification) -> AudioInterruption {
    guard notification.name == AVAudioSession.interruptionNotification,
      let userInfo = notification.userInfo,
      let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else { Assert.fatal("Interruption: \(notification) is invalid") }

    switch type {
    case .began:
      return .pause
    case .ended:
      guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt
      else { Assert.fatal("Interruption options: \(userInfo) is invalid") }

      let options = AVAudioSession.InterruptionOptions(
        rawValue: optionsValue
      )
      if options.contains(.shouldResume) {
        return .resume
      }
    @unknown default:
      break
    }
    return .ignore
  }
}
