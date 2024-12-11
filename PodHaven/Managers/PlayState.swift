// Copyright Justin Bishop, 2024

import Foundation

@Observable @MainActor final class PlayState: Sendable {
  static let shared = { PlayState() }()

  var isPlayable = false
  var isPlaying = false

  fileprivate init() {

  }
}
