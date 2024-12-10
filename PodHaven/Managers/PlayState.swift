// Copyright Justin Bishop, 2024

import Foundation

@Observable @MainActor final class PlayState: Sendable {
  static let shared = { PlayState() }()

  fileprivate init() {

  }
}
