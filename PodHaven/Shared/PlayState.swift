// Copyright Justin Bishop, 2024

import AVFoundation
import Foundation

@dynamicMemberLookup
@Observable @MainActor final class PlayState: Sendable {
  static let shared = PlayState()

  // MARK: - Meta

  static subscript<T>(dynamicMember keyPath: KeyPath<PlayState, T>) -> T {
    shared[keyPath: keyPath]
  }

  subscript<T>(dynamicMember keyPath: KeyPath<PlayState.Status, T>) -> T {
    status[keyPath: keyPath]
  }

  // MARK: - State Getters

  enum Status: Sendable {
    case loading, active, playing, paused, stopped, waiting

    var playable: Bool {
      switch self {
      case .active, .playing, .paused, .waiting: return true
      default: return false
      }
    }

    var loading: Bool { self == .loading }
    var active: Bool { self == .active }
    var playing: Bool { self == .playing }
    var paused: Bool { self == .paused }
    var stopped: Bool { self == .stopped }
    var waiting: Bool { self == .waiting }
  }

  private(set) var status: Status = .stopped
  private(set) var duration = CMTime.zero
  private(set) var currentTime = CMTime.zero
  private(set) var onDeck: PodcastEpisode?
  private init() {}

  // MARK: - State Setters

  func setStatus(_ status: Status, _ key: PlayManagerAccessKey) {
    self.status = status
  }

  func setDuration(_ duration: CMTime, _ key: PlayManagerAccessKey) {
    self.duration = duration
  }

  func setCurrentTime(_ currentTime: CMTime, _ key: PlayManagerAccessKey) {
    self.currentTime = currentTime
  }

  func setOnDeck(_ onDeck: PodcastEpisode, _ key: PlayManagerAccessKey) {
    self.onDeck = onDeck
  }
}
