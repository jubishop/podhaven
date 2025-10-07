// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

final class FakeCommandCenter: CommandableCenter, Sendable {
  // MARK: - State Management

  let stream: AsyncStream<CommandCenter.Command>
  private let continuation: AsyncStream<CommandCenter.Command>.Continuation
  let registrationCalls = ThreadSafe(0)

  init() {
    (self.stream, self.continuation) = AsyncStream.makeStream(of: CommandCenter.Command.self)
    registerRemoteCommandHandlers()
  }

  func registerRemoteCommandHandlers() {
    registrationCalls { $0 += 1 }
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
