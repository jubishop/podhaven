// Copyright Justin Bishop, 2025

import Foundation
import MediaPlayer

struct CommandCenter: Sendable {
  enum Command {
    case play, pause, togglePlayPause
    case skipBackward(TimeInterval)
    case skipForward(TimeInterval)
    case playbackPosition(TimeInterval)
  }

  // MARK: - State Management

  private var stream: AsyncStream<Command>
  private var continuation: AsyncStream<Command>.Continuation

  // MARK: - Convenience Getters

  var commandCenter: MPRemoteCommandCenter { MPRemoteCommandCenter.shared() }
  init(_ key: PlayManagerAccessKey) {
    (self.stream, self.continuation) = AsyncStream.makeStream(of: Command.self)
  }

  func commandStream() -> AsyncStream<Command> { stream }

  // MARK: - Public Functions

  mutating func start() {
    stop()
    print("starting command center")
    let continuation = self.continuation
    commandCenter.playCommand.addTarget { event in
      continuation.yield(.play)
      return .success
    }
    commandCenter.pauseCommand.addTarget { event in
      continuation.yield(.pause)
      return .success
    }
    commandCenter.togglePlayPauseCommand.addTarget { event in
      continuation.yield(.togglePlayPause)
      return .success
    }
    commandCenter.skipForwardCommand.preferredIntervals = [30]
    commandCenter.skipForwardCommand.addTarget { event in
      guard let skipEvent = event as? MPSkipIntervalCommandEvent
      else { fatalError("Event is not a MPSkipIntervalCommandEvent") }

      continuation.yield(.skipForward(skipEvent.interval))
      return .success
    }
    commandCenter.skipBackwardCommand.preferredIntervals = [15]
    commandCenter.skipBackwardCommand.addTarget { event in
      guard let skipEvent = event as? MPSkipIntervalCommandEvent
      else { fatalError("Event is not a MPSkipIntervalCommandEvent") }

      continuation.yield(.skipBackward(skipEvent.interval))
      return .success
    }
    commandCenter.changePlaybackPositionCommand.addTarget { event in
      guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent
      else { fatalError("Event is not a MPChangePlaybackPositionCommandEvent") }

      continuation.yield(.playbackPosition(positionEvent.positionTime))
      return .success
    }
  }

  mutating func stop() {
    print("stopping command center")
    commandCenter.playCommand.removeTarget(nil)
    commandCenter.pauseCommand.removeTarget(nil)
    commandCenter.togglePlayPauseCommand.removeTarget(nil)
    commandCenter.skipForwardCommand.removeTarget(nil)
    commandCenter.skipBackwardCommand.removeTarget(nil)
    commandCenter.changePlaybackPositionCommand.removeTarget(nil)
  }
}
