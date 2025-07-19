// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

extension AVPlayerItem.Status: @retroactive CustomStringConvertible {
  public var description: String {
    switch self {
    case .unknown: return "unknown"
    case .readyToPlay: return "readyToPlay"
    case .failed: return "failed"
    @unknown default: return "unknown(\(rawValue))"
    }
  }
}

extension AVPlayer.TimeControlStatus: @retroactive CustomStringConvertible {
  public var description: String {
    switch self {
    case .paused: return "paused"
    case .waitingToPlayAtSpecifiedRate: return "waitingToPlayAtSpecifiedRate"
    case .playing: return "playing"
    @unknown default: return "unknown(\(rawValue))"
    }
  }
}
