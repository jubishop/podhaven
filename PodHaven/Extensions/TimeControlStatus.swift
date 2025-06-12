// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

extension AVPlayer.TimeControlStatus: @retroactive CustomStringConvertible {
  public var description: String {
    switch self {
    case .paused:
      return "paused"
    case .waitingToPlayAtSpecifiedRate:
      return "waitingToPlayAtSpecifiedRate"
    case .playing:
      return "playing"
    @unknown default:
      Assert.fatal("Unknown TimeControlStatus enum")
    }
  }
}
