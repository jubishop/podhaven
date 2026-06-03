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
    case playbackPosition(
      TimeInterval,
      sourceEpisodeID: Episode.ID?,
      eventTimestamp: TimeInterval
    )
    case changePlaybackRate(Float)
    case nextEpisode
    case previousEpisode
    case bookmark(sourceEpisodeID: Episode.ID?)
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
    commandCenter.bookmark.removeCommandTarget()

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

      yield(
        .playbackPosition(
          positionEvent.positionTime,
          sourceEpisodeID: Container.shared.sharedState().$onDeck.value?.id,
          eventTimestamp: positionEvent.timestamp
        )
      )
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
    commandCenter.bookmark.localizedTitle = "Save"
    commandCenter.bookmark.localizedShortTitle = "Save"
    commandCenter.bookmark.addCommandTarget { event in
      yield(.bookmark(sourceEpisodeID: Container.shared.sharedState().$onDeck.value?.id))
      return .success
    }

    commandCenter.play.isEnabled = true
    commandCenter.pause.isEnabled = true
    commandCenter.togglePlayPause.isEnabled = true
    commandCenter.skipForward.isEnabled = true
    commandCenter.skipBackward.isEnabled = true
    commandCenter.changePlaybackRate.isEnabled = true
    commandCenter.bookmark.isEnabled = true
    commandCenter.like.isEnabled = false
    commandCenter.dislike.isEnabled = false
    commandCenter.rating.isEnabled = false

    updateSkipIntervals()
    updateNextTrack()
    updateScrubbing()
    updateBookmark()
  }

  static func updateBookmark() {
    let saveInCache = Container.shared.sharedState().$onDeck.value?.saveInCache ?? false
    let bookmark = Container.shared.mpRemoteCommandCenter().bookmark
    guard bookmark.isActive != saveInCache else { return }

    log.debug("updateBookmark: bookmark isActive: \(saveInCache)")
    bookmark.isActive = saveInCache
  }

  static func updateScrubbing() {
    let enabled = Container.shared.userSettings().commandCenterScrubbingEnabled
    log.debug("updateScrubbing: changePlaybackPosition enabled: \(enabled)")

    Container.shared.mpRemoteCommandCenter().changePlaybackPosition.isEnabled = enabled
  }

  static func updateSkipIntervals() {
    let userSettings = Container.shared.userSettings()
    log.debug(
      """
      updateSkipIntervals: forward \(userSettings.skipForwardInterval)s, \
      backward \(userSettings.skipBackwardInterval)s
      """
    )

    let commandCenter = Container.shared.mpRemoteCommandCenter()
    commandCenter.skipForward.preferredIntervals = [userSettings.skipForwardInterval as NSNumber]
    commandCenter.skipBackward.preferredIntervals = [userSettings.skipBackwardInterval as NSNumber]
  }

  static func updateNextTrack() {
    let commandCenter = Container.shared.mpRemoteCommandCenter()
    let sharedState = Container.shared.sharedState()
    let onDeckID = sharedState.$onDeck.value?.id
    let previousTrackEnabled = onDeckID != nil
    commandCenter.previousTrack.isEnabled = previousTrackEnabled
    log.debug(
      """
      updateNextTrack: previousTrack enabled: \(previousTrackEnabled) \
      (onDeckID: \(String(describing: onDeckID)))
      """
    )

    switch Container.shared.userSettings().nextTrackBehavior {
    case .nextEpisode:
      let queueCount = sharedState.$queuedPodcastEpisodes.value.count
      let enabled = queueCount > 0
      log.debug("updateNextTrack: nextEpisode, enabled: \(enabled) (queueCount: \(queueCount))")
      commandCenter.nextTrack.isEnabled = enabled
    case .skipInterval, .nextChapter:
      log.debug("updateNextTrack: enabled (skipInterval/nextChapter)")
      commandCenter.nextTrack.isEnabled = true
    }
  }
}
