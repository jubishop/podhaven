// Copyright Justin Bishop, 2025

import Foundation
import MediaPlayer

@testable import PodHaven

// MARK: - Fake Commands

protocol FakeMPRemoteCommandable: MPRemoteCommandable {
  var handler: ((any MPRemoteCommandEventable) -> MPRemoteCommandHandlerStatus)? { get set }
  func fire(_ event: any MPRemoteCommandEventable)
}
extension FakeMPRemoteCommandable {
  func addCommandTarget(
    handler: @escaping (any MPRemoteCommandEventable) -> MPRemoteCommandHandlerStatus
  ) {
    self.handler = handler
  }

  func removeCommandTarget() {
    handler = nil
  }

  func fire(_ event: any MPRemoteCommandEventable) {
    if isEnabled {
      _ = handler?(event)
    }
  }
}

final class FakeMPRemoteCommand: FakeMPRemoteCommandable {
  var handler: ((any MPRemoteCommandEventable) -> MPRemoteCommandHandlerStatus)?
  var isEnabled: Bool = false
}

final class FakeMPSkipCommand: FakeMPRemoteCommandable, MPSkipCommandable {
  var handler: ((any MPRemoteCommandEventable) -> MPRemoteCommandHandlerStatus)?
  var isEnabled: Bool = false
  var preferredIntervals: [NSNumber] = []
}

final class FakeMPChangePlaybackRateCommand:
  FakeMPRemoteCommandable,
  MPChangePlaybackRateCommandable
{
  var handler: ((any MPRemoteCommandEventable) -> MPRemoteCommandHandlerStatus)?
  var isEnabled: Bool = false
  var supportedPlaybackRates: [NSNumber] = []
}

final class FakeMPFeedbackCommand: FakeMPRemoteCommandable, MPFeedbackCommandable {
  var handler: ((any MPRemoteCommandEventable) -> MPRemoteCommandHandlerStatus)?
  var isEnabled: Bool = false
  var isActive: Bool = false
  var localizedTitle: String = ""
  var localizedShortTitle: String = ""
}

// MARK: - Fake Events

class FakeMPRemoteCommandEvent: MPRemoteCommandEventable {
  let timestamp: TimeInterval

  init(timestamp: TimeInterval = Date().timeIntervalSinceReferenceDate) {
    self.timestamp = timestamp
  }
}

class FakeMPSkipIntervalCommandEvent: MPSkipIntervalCommandEventable {
  let interval: TimeInterval
  let timestamp: TimeInterval

  init(interval: TimeInterval, timestamp: TimeInterval = Date().timeIntervalSinceReferenceDate) {
    self.interval = interval
    self.timestamp = timestamp
  }
}

class FakeMPChangePlaybackPositionCommandEvent: MPChangePlaybackPositionCommandEventable {
  let positionTime: TimeInterval
  let timestamp: TimeInterval

  init(
    positionTime: TimeInterval,
    timestamp: TimeInterval = Date().timeIntervalSinceReferenceDate
  ) {
    self.positionTime = positionTime
    self.timestamp = timestamp
  }
}

class FakeMPChangePlaybackRateCommandEvent: MPChangePlaybackRateCommandEventable {
  let playbackRate: Float
  let timestamp: TimeInterval

  init(playbackRate: Float, timestamp: TimeInterval = Date().timeIntervalSinceReferenceDate) {
    self.playbackRate = playbackRate
    self.timestamp = timestamp
  }
}

// MARK: - Fake CommandCenter

final class FakeMPRemoteCommandCenter: MPRemoteCommandableCenter {
  private let _playCommand: FakeMPRemoteCommand
  private let _pauseCommand: FakeMPRemoteCommand
  private let _togglePlayPauseCommand: FakeMPRemoteCommand
  private let _skipForwardCommand: FakeMPSkipCommand
  private let _skipBackwardCommand: FakeMPSkipCommand
  private let _changePlaybackPositionCommand: FakeMPRemoteCommand
  private let _changePlaybackRateCommand: FakeMPChangePlaybackRateCommand
  private let _nextTrackCommand: FakeMPRemoteCommand
  private let _previousTrackCommand: FakeMPRemoteCommand
  private let _likeCommand: FakeMPFeedbackCommand
  private let _dislikeCommand: FakeMPFeedbackCommand
  private let _bookmarkCommand: FakeMPFeedbackCommand
  private let _ratingCommand: FakeMPRemoteCommand

  init() {
    self._playCommand = FakeMPRemoteCommand()
    self._pauseCommand = FakeMPRemoteCommand()
    self._togglePlayPauseCommand = FakeMPRemoteCommand()
    self._skipForwardCommand = FakeMPSkipCommand()
    self._skipBackwardCommand = FakeMPSkipCommand()
    self._changePlaybackPositionCommand = FakeMPRemoteCommand()
    self._changePlaybackRateCommand = FakeMPChangePlaybackRateCommand()
    self._nextTrackCommand = FakeMPRemoteCommand()
    self._previousTrackCommand = FakeMPRemoteCommand()
    self._likeCommand = FakeMPFeedbackCommand()
    self._dislikeCommand = FakeMPFeedbackCommand()
    self._bookmarkCommand = FakeMPFeedbackCommand()
    self._ratingCommand = FakeMPRemoteCommand()
  }

  var play: any MPRemoteCommandable { _playCommand }
  var pause: any MPRemoteCommandable { _pauseCommand }
  var togglePlayPause: any MPRemoteCommandable { _togglePlayPauseCommand }
  var skipForward: any MPSkipCommandable { _skipForwardCommand }
  var skipBackward: any MPSkipCommandable { _skipBackwardCommand }
  var changePlaybackPosition: any MPRemoteCommandable { _changePlaybackPositionCommand }
  var changePlaybackRate: any MPChangePlaybackRateCommandable { _changePlaybackRateCommand }
  var nextTrack: any MPRemoteCommandable { _nextTrackCommand }
  var previousTrack: any MPRemoteCommandable { _previousTrackCommand }
  var like: any MPFeedbackCommandable { _likeCommand }
  var dislike: any MPFeedbackCommandable { _dislikeCommand }
  var bookmark: any MPFeedbackCommandable { _bookmarkCommand }
  var rating: any MPRemoteCommandable { _ratingCommand }

  // MARK: - Testing Manipulators

  func firePlay() {
    _playCommand.fire(FakeMPRemoteCommandEvent())
  }

  func firePause() {
    _pauseCommand.fire(FakeMPRemoteCommandEvent())
  }

  func fireTogglePlayPause() {
    _togglePlayPauseCommand.fire(FakeMPRemoteCommandEvent())
  }

  func fireSkipForward(_ interval: TimeInterval) {
    let event = FakeMPSkipIntervalCommandEvent(interval: interval)
    _skipForwardCommand.fire(event)
  }

  func fireSkipBackward(_ interval: TimeInterval) {
    let event = FakeMPSkipIntervalCommandEvent(interval: interval)
    _skipBackwardCommand.fire(event)
  }

  func fireSeek(to position: TimeInterval) {
    let event = FakeMPChangePlaybackPositionCommandEvent(positionTime: position)
    _changePlaybackPositionCommand.fire(event)
  }

  func fireChangePlaybackRate(_ rate: Float) {
    let event = FakeMPChangePlaybackRateCommandEvent(playbackRate: rate)
    _changePlaybackRateCommand.fire(event)
  }

  func fireNextTrack() {
    _nextTrackCommand.fire(FakeMPRemoteCommandEvent())
  }

  func firePreviousTrack() {
    _previousTrackCommand.fire(FakeMPRemoteCommandEvent())
  }

  func fireBookmark() {
    _bookmarkCommand.fire(FakeMPRemoteCommandEvent())
  }

  func fireLike() {
    _likeCommand.fire(FakeMPRemoteCommandEvent())
  }

  func fireDislike() {
    _dislikeCommand.fire(FakeMPRemoteCommandEvent())
  }
}
