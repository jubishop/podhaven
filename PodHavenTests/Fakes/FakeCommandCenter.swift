// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

class FakeCommandCenter: CommandableCenter {
  // MARK: - State Management

  let stream: AsyncStream<CommandCenter.Command>
  private let continuation: AsyncStream<CommandCenter.Command>.Continuation
  var seekCommandsEnabled = false

  init() {
    (self.stream, self.continuation) = AsyncStream.makeStream(of: CommandCenter.Command.self)
  }

  // MARK: - Testing Manipulators

  func play() {
    continuation.yield(.play)
  }

  func pause() {
    continuation.yield(.pause)
  }

  func togglePlayPause() {
    continuation.yield(.togglePlayPause)
  }

  func seek(to position: TimeInterval) {
    continuation.yield(.playbackPosition(position))
  }

  func skipForward(_ amount: TimeInterval) {
    continuation.yield(.skipForward(amount))
  }

  func skipBackward(_ amount: TimeInterval) {
    continuation.yield(.skipBackward(amount))
  }
}
