// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import MediaPlayer

extension Container {
  var commandCenter: Factory<CommandableCenter> {
    Factory(self) { CommandCenter() }.scope(.cached)
  }
}

struct CommandCenter: CommandableCenter {
  enum Command {
    case play, pause, togglePlayPause
    case skipBackward(TimeInterval)
    case skipForward(TimeInterval)
    case playbackPosition(TimeInterval)
  }

  private static let log = Log.as(LogSubsystem.Play.commandCenter)

  // MARK: - State Management

  let stream: AsyncStream<Command>
  private let continuation: AsyncStream<Command>.Continuation

  // MARK: - Initialization

  init() {
    (self.stream, self.continuation) = AsyncStream.makeStream(of: Command.self)
    registerRemoteCommandHandlers()
  }

  func registerRemoteCommandHandlers() {
    let commandCenter = MPRemoteCommandCenter.shared()

    commandCenter.playCommand.removeTarget(nil)
    commandCenter.pauseCommand.removeTarget(nil)
    commandCenter.togglePlayPauseCommand.removeTarget(nil)
    commandCenter.skipForwardCommand.removeTarget(nil)
    commandCenter.skipBackwardCommand.removeTarget(nil)
    commandCenter.changePlaybackPositionCommand.removeTarget(nil)

    commandCenter.playCommand.isEnabled = true
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.skipForwardCommand.isEnabled = true
    commandCenter.skipBackwardCommand.isEnabled = true
    commandCenter.changePlaybackPositionCommand.isEnabled = true

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
      else { Assert.fatal("Event is not a MPSkipIntervalCommandEvent") }

      continuation.yield(.skipForward(skipEvent.interval))
      return .success
    }
    commandCenter.skipBackwardCommand.preferredIntervals = [15]
    commandCenter.skipBackwardCommand.addTarget { event in
      guard let skipEvent = event as? MPSkipIntervalCommandEvent
      else { Assert.fatal("Event is not a MPSkipIntervalCommandEvent") }

      continuation.yield(.skipBackward(skipEvent.interval))
      return .success
    }
    commandCenter.changePlaybackPositionCommand.addTarget { [continuation] event in
      guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent
      else { Assert.fatal("Event is not a MPChangePlaybackPositionCommandEvent") }

      continuation.yield(.playbackPosition(positionEvent.positionTime))
      return .success
    }
  }
}
