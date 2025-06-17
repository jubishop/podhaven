// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

enum PlaybackStatus: CustomStringConvertible {
  case paused
  case playing
  case waitingToPlayAtSpecifiedRate
  case seeking

  init(_ timeControlStatus: AVPlayer.TimeControlStatus) {
    switch timeControlStatus {
    case .paused:
      self = .paused
    case .playing:
      self = .playing
    case .waitingToPlayAtSpecifiedRate:
      self = .waitingToPlayAtSpecifiedRate
    @unknown default:
      Assert.fatal("Unknown time control status: \(timeControlStatus)")
    }
  }

  var timeControlStatus: AVPlayer.TimeControlStatus? {
    switch self {
    case .paused:
      return .paused
    case .playing:
      return .playing
    case .waitingToPlayAtSpecifiedRate:
      return .waitingToPlayAtSpecifiedRate
    case .seeking:
      return nil
    }
  }

  // MARK: - CustomStringConvertible

  var description: String {
    switch self {
    case .paused:
      return "paused"
    case .playing:
      return "playing"
    case .waitingToPlayAtSpecifiedRate:
      return "waitingToPlayAtSpecifiedRate"
    case .seeking:
      return "seeking"
    }
  }
}
