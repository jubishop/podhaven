// Copyright Justin Bishop, 2025

enum PlaybackStatus: Codable, Equatable, CustomStringConvertible, Sendable {
  case loading(String)
  case paused, playing, stopped, waiting

  var loading: Bool {
    if case .loading = self { return true }
    return false
  }

  var loadingTitle: String? {
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
    case .stopped:
      return "stopped"
    case .waiting:
      return "waiting"
    }
  }
}
