// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import MediaPlayer

extension Container {
  var commandCenter: Factory<CommandCenter> {
    Factory(self) { CommandCenter() }.scope(.cached)
  }
}

struct CommandCenter {
  enum Command {
    case play, pause, togglePlayPause
    case skipBackward(TimeInterval)
    case skipForward(TimeInterval)
    case playbackPosition(TimeInterval)
  }

  // MARK: - State Management

  let stream: AsyncStream<Command>
  private let continuation: AsyncStream<Command>.Continuation

  // MARK: - Convenience Getters

  var commandCenter: MPRemoteCommandCenter { MPRemoteCommandCenter.shared() }
  fileprivate init() {
    (self.stream, self.continuation) = AsyncStream.makeStream(of: Command.self)

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
    commandCenter.changePlaybackPositionCommand.addTarget { event in
      guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent
      else { Assert.fatal("Event is not a MPChangePlaybackPositionCommandEvent") }

      continuation.yield(.playbackPosition(positionEvent.positionTime))
      return .success
    }
  }
}
