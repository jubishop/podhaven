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

  // MARK: - CommandableCenter

  func disableSeekCommands() {
    seekCommandsEnabled = false
  }

  func enableSeekCommands() {
    seekCommandsEnabled = true
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
    guard seekCommandsEnabled else { return }
    continuation.yield(.playbackPosition(position))
  }
}
