// Copyright Justin Bishop, 2024

import Foundation
import MediaPlayer

final class CommandCenter {
  enum Command {
    case play, pause
  }

  private let commandCenter = MPRemoteCommandCenter.shared()
  private var stream: AsyncStream<Command>?
  private var continuation: AsyncStream<Command>.Continuation?

  init(_ key: PlayManagerAccessKey) {}

  func commands() -> AsyncStream<Command> {
    guard let stream = self.stream else {
      fatalError("Calling commands() when no async stream")
    }
    return stream
  }

  func begin() {
    stop()
    let (stream, continuation) = AsyncStream.makeStream(of: Command.self)
    self.stream = stream
    self.continuation = continuation
    commandCenter.playCommand.addTarget { event in
      continuation.yield(.play)
      return .success
    }
    commandCenter.pauseCommand.addTarget { event in
      continuation.yield(.pause)
      return .success
    }
  }

  func stop() {
    commandCenter.playCommand.removeTarget(nil)
    commandCenter.pauseCommand.removeTarget(nil)
    if let continuation = self.continuation {
      continuation.finish()
      self.continuation = nil
    }
  }
}
