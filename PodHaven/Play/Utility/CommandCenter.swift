// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import MediaPlayer

extension Container {
  var commandCenterStream:
    Factory<
      (
        stream: AsyncStream<CommandCenter.Command>,
        continuation: AsyncStream<CommandCenter.Command>.Continuation
      )
    >
  {
    Factory(self) {
      AsyncStream.makeStream(of: CommandCenter.Command.self)
    }
    .scope(.cached)
  }
}

enum CommandCenter: Sendable {
  enum Command {
    case play, pause, togglePlayPause
    case skipBackward(TimeInterval)
    case skipForward(TimeInterval)
    case playbackPosition(TimeInterval)
    case changePlaybackRate(Float)
    case nextEpisode
    case previousEpisode
  }

  private static let log = Log.as(LogSubsystem.Play.commandCenter)

  static func registerRemoteCommandHandlers() {
    log.debug("Now registering remote command handlers")

    let appLauncher = Container.shared.appLauncher()
    let commandCenter = Container.shared.mpRemoteCommandCenter()
    let continuation = Container.shared.commandCenterStream().continuation

    let yield: (Command) -> Void = { command in
      log.debug("Remote command received: \(command)")
      Task {
        await appLauncher.prepareForPlayback()
        continuation.yield(command)
      }
    }

    commandCenter.play.removeCommandTarget()
    commandCenter.pause.removeCommandTarget()
    commandCenter.togglePlayPause.removeCommandTarget()
    commandCenter.skipForward.removeCommandTarget()
    commandCenter.skipBackward.removeCommandTarget()
    commandCenter.changePlaybackPosition.removeCommandTarget()
    commandCenter.changePlaybackRate.removeCommandTarget()
    commandCenter.nextTrack.removeCommandTarget()
    commandCenter.previousTrack.removeCommandTarget()

    commandCenter.play.addCommandTarget { event in
      yield(.play)
      return .success
    }
    commandCenter.pause.addCommandTarget { event in
      yield(.pause)
      return .success
    }
    commandCenter.togglePlayPause.addCommandTarget { event in
      yield(.togglePlayPause)
      return .success
    }
    commandCenter.skipForward.addCommandTarget { event in
      guard let skipEvent = event as? any MPSkipIntervalCommandEventable
      else { Assert.fatal("Event is not a MPSkipIntervalCommandEventable") }

      yield(.skipForward(skipEvent.interval))
      return .success
    }
    commandCenter.skipBackward.addCommandTarget { event in
      guard let skipEvent = event as? any MPSkipIntervalCommandEventable
      else { Assert.fatal("Event is not a MPSkipIntervalCommandEventable") }

      yield(.skipBackward(skipEvent.interval))
      return .success
    }
    commandCenter.changePlaybackPosition.addCommandTarget { event in
      guard let positionEvent = event as? any MPChangePlaybackPositionCommandEventable
      else { Assert.fatal("Event is not a MPChangePlaybackPositionCommandEventable") }

      yield(.playbackPosition(positionEvent.positionTime))
      return .success
    }
    commandCenter.changePlaybackRate.supportedPlaybackRates =
      stride(from: 0.8, through: 2.0, by: 0.1).map { NSNumber(value: $0) }
    commandCenter.changePlaybackRate.addCommandTarget { event in
      guard let rateEvent = event as? any MPChangePlaybackRateCommandEventable
      else { Assert.fatal("Event is not a MPChangePlaybackRateCommandEventable") }

      yield(.changePlaybackRate(rateEvent.playbackRate))
      return .success
    }
    commandCenter.nextTrack.addCommandTarget { event in
      yield(.nextEpisode)
      return .success
    }
    commandCenter.previousTrack.addCommandTarget { event in
      yield(.previousEpisode)
      return .success
    }

    commandCenter.play.isEnabled = true
    commandCenter.pause.isEnabled = true
    commandCenter.togglePlayPause.isEnabled = true
    commandCenter.skipForward.isEnabled = true
    commandCenter.skipBackward.isEnabled = true
    commandCenter.changePlaybackPosition.isEnabled = true
    commandCenter.changePlaybackRate.isEnabled = true
    commandCenter.like.isEnabled = false
    commandCenter.dislike.isEnabled = false
    commandCenter.bookmark.isEnabled = false
    commandCenter.rating.isEnabled = false

    updateSkipIntervals()
    updateNextTrack()
  }

  static func updateSkipIntervals() {
    log.debug("updateSkipIntervals")

    let commandCenter = Container.shared.mpRemoteCommandCenter()
    let userSettings = Container.shared.userSettings()

    commandCenter.skipForward.preferredIntervals = [userSettings.skipForwardInterval as NSNumber]
    commandCenter.skipBackward.preferredIntervals = [userSettings.skipBackwardInterval as NSNumber]
  }

  static func updateNextTrack() {
    log.debug("updateNextTrack")

    let commandCenter = Container.shared.mpRemoteCommandCenter()
    commandCenter.previousTrack.isEnabled = true

    switch Container.shared.userSettings().nextTrackBehavior {
    case .nextEpisode:
      commandCenter.nextTrack.isEnabled = Container.shared.sharedState().queueCount > 0
    case .skipInterval, .nextChapter:
      commandCenter.nextTrack.isEnabled = true
    }
  }
}
