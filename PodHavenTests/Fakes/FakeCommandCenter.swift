// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

struct FakeCommandCenter: CommandableCenter {
  // MARK: - State Management

  let stream: AsyncStream<CommandCenter.Command>
  let continuation: AsyncStream<CommandCenter.Command>.Continuation
  private var seekCommandsEnabled = true

  init() {
    (self.stream, self.continuation) = AsyncStream.makeStream(of: CommandCenter.Command.self)
  }

  func disableSeekCommands() {
    seekCommandsEnabled = false
  }

  func enableSeekCommands() {
    seekCommandsEnabled = true
  }
}
