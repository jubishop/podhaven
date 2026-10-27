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
    handler: @escaping @Sendable (any MPRemoteCommandEventable) -> MPRemoteCommandHandlerStatus
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

// MediaPlayer command objects are not thread-safe, so record writes made off
// the main thread.
final class FakeMPRemoteCommandWrites: Sendable {
  private let offMainWrites = ThreadSafe<[String]>([])

  var offMain: [String] { offMainWrites() }

  func record(_ name: String, _ property: String) {
    guard !Thread.isMainThread else { return }
    offMainWrites { $0.append("\(name).\(property)") }
  }
}

final class FakeMPRemoteCommand: FakeMPRemoteCommandable {
  private let name: String
  private let writes: FakeMPRemoteCommandWrites

  var handler: ((any MPRemoteCommandEventable) -> MPRemoteCommandHandlerStatus)? {
    didSet { writes.record(name, "handler") }
  }
  var isEnabled: Bool = false {
    didSet { writes.record(name, "isEnabled") }
  }

  nonisolated init(_ name: String, writes: FakeMPRemoteCommandWrites) {
    self.name = name
    self.writes = writes
  }
}

final class FakeMPSkipCommand: FakeMPRemoteCommandable, MPSkipCommandable {
  private let name: String
  private let writes: FakeMPRemoteCommandWrites

  var handler: ((any MPRemoteCommandEventable) -> MPRemoteCommandHandlerStatus)? {
    didSet { writes.record(name, "handler") }
  }
  var isEnabled: Bool = false {
    didSet { writes.record(name, "isEnabled") }
  }
  var preferredIntervals: [NSNumber] = [] {
    didSet { writes.record(name, "preferredIntervals") }
  }

  nonisolated init(_ name: String, writes: FakeMPRemoteCommandWrites) {
    self.name = name
    self.writes = writes
  }
}

final class FakeMPChangePlaybackRateCommand:
  FakeMPRemoteCommandable,
  MPChangePlaybackRateCommandable
{
  private let name: String
  private let writes: FakeMPRemoteCommandWrites

  var handler: ((any MPRemoteCommandEventable) -> MPRemoteCommandHandlerStatus)? {
    didSet { writes.record(name, "handler") }
  }
  var isEnabled: Bool = false {
    didSet { writes.record(name, "isEnabled") }
  }
  var supportedPlaybackRates: [NSNumber] = [] {
    didSet { writes.record(name, "supportedPlaybackRates") }
  }

  nonisolated init(_ name: String, writes: FakeMPRemoteCommandWrites) {
    self.name = name
    self.writes = writes
  }
}

final class FakeMPFeedbackCommand: FakeMPRemoteCommandable, MPFeedbackCommandable {
  private let name: String
  private let writes: FakeMPRemoteCommandWrites

  var handler: ((any MPRemoteCommandEventable) -> MPRemoteCommandHandlerStatus)? {
    didSet { writes.record(name, "handler") }
  }
  var isEnabled: Bool = false {
    didSet { writes.record(name, "isEnabled") }
  }
  var isActive: Bool = false {
    didSet { writes.record(name, "isActive") }
  }
  var localizedTitle: String = "" {
    didSet { writes.record(name, "localizedTitle") }
  }
  var localizedShortTitle: String = "" {
    didSet { writes.record(name, "localizedShortTitle") }
  }

  nonisolated init(_ name: String, writes: FakeMPRemoteCommandWrites) {
    self.name = name
    self.writes = writes
  }
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

  nonisolated let writes: FakeMPRemoteCommandWrites

  nonisolated init() {
    let writes = FakeMPRemoteCommandWrites()
    self.writes = writes
    self._playCommand = FakeMPRemoteCommand("play", writes: writes)
    self._pauseCommand = FakeMPRemoteCommand("pause", writes: writes)
    self._togglePlayPauseCommand = FakeMPRemoteCommand("togglePlayPause", writes: writes)
    self._skipForwardCommand = FakeMPSkipCommand("skipForward", writes: writes)
    self._skipBackwardCommand = FakeMPSkipCommand("skipBackward", writes: writes)
    self._changePlaybackPositionCommand = FakeMPRemoteCommand(
      "changePlaybackPosition",
      writes: writes
    )
    self._changePlaybackRateCommand = FakeMPChangePlaybackRateCommand(
      "changePlaybackRate",
      writes: writes
    )
    self._nextTrackCommand = FakeMPRemoteCommand("nextTrack", writes: writes)
    self._previousTrackCommand = FakeMPRemoteCommand("previousTrack", writes: writes)
    self._likeCommand = FakeMPFeedbackCommand("like", writes: writes)
    self._dislikeCommand = FakeMPFeedbackCommand("dislike", writes: writes)
    self._bookmarkCommand = FakeMPFeedbackCommand("bookmark", writes: writes)
    self._ratingCommand = FakeMPRemoteCommand("rating", writes: writes)
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
