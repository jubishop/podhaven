// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

enum PlaybackStatus: Equatable, CustomStringConvertible {
  case loading(String)
  case paused, playing, seeking, stopped, waiting

  init(_ timeControlStatus: AVPlayer.TimeControlStatus) {
    switch timeControlStatus {
    case .paused:
      self = .paused
    case .playing:
      self = .playing
    case .waitingToPlayAtSpecifiedRate:
      self = .waiting
    @unknown default:
      Assert.fatal("Unknown time control status: \(timeControlStatus)")
    }
  }

  var loading: String? {
    if case .loading(let title) = self { return title }
    return nil
  }

  var paused: Bool {
    if case .paused = self { return true }
    return false
  }

  var playing: Bool {
    if case .playing = self { return true }
    return false
  }

  var seeking: Bool {
    if case .seeking = self { return true }
    return false
  }

  var stopped: Bool {
    if case .stopped = self { return true }
    return false
  }

  var waiting: Bool {
    if case .waiting = self { return true }
    return false
  }

  var description: String {
    switch self {
    case .loading(let title):
      return "loading(\(title))"
    case .paused:
      return "paused"
    case .playing:
      return "playing"
    case .seeking:
      return "seeking"
    case .stopped:
      return "stopped"
    case .waiting:
      return "waiting"
    }
  }
}
