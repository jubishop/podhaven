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

final class FakeMPChangePlaybackRateCommand: FakeMPRemoteCommandable,
  MPChangePlaybackRateCommandable
{
  var handler: ((any MPRemoteCommandEventable) -> MPRemoteCommandHandlerStatus)?
  var isEnabled: Bool = false
  var supportedPlaybackRates: [NSNumber] = []
}

// MARK: - Fake Events

class FakeMPRemoteCommandEvent: MPRemoteCommandEventable {}

class FakeMPSkipIntervalCommandEvent: MPSkipIntervalCommandEventable {
  let interval: TimeInterval

  init(interval: TimeInterval) {
    self.interval = interval
  }
}

class FakeMPChangePlaybackPositionCommandEvent: MPChangePlaybackPositionCommandEventable {
  let positionTime: TimeInterval

  init(positionTime: TimeInterval) {
    self.positionTime = positionTime
  }
}

class FakeMPChangePlaybackRateCommandEvent: MPChangePlaybackRateCommandEventable {
  let playbackRate: Float

  init(playbackRate: Float) {
    self.playbackRate = playbackRate
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
  private let _likeCommand: FakeMPRemoteCommand
  private let _dislikeCommand: FakeMPRemoteCommand
  private let _bookmarkCommand: FakeMPRemoteCommand
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
    self._likeCommand = FakeMPRemoteCommand()
    self._dislikeCommand = FakeMPRemoteCommand()
    self._bookmarkCommand = FakeMPRemoteCommand()
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
  var like: any MPRemoteCommandable { _likeCommand }
  var dislike: any MPRemoteCommandable { _dislikeCommand }
  var bookmark: any MPRemoteCommandable { _bookmarkCommand }
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
}
