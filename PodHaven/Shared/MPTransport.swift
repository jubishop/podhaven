// Copyright Justin Bishop, 2024

import Foundation
import MediaPlayer

@globalActor
final actor MPActor {
  static let shared = MPActor()
}

@MPActor
final class MPTransport {
  static let shared = MPTransport()

  func updateNowPlayingInfo() {

  }
}
