// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

struct FakeCommandCenter: CommandableCenter {
  // MARK: - State Management

  let stream: AsyncStream<CommandCenter.Command>
  let continuation: AsyncStream<CommandCenter.Command>.Continuation

  init() {
    (self.stream, self.continuation) = AsyncStream.makeStream(of: CommandCenter.Command.self)
  }
}
