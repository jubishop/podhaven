// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation

@testable import PodHaven

@MainActor
class FakeAVPlayer: AVPlayable, Identifiable, Equatable {
  let id = UUID()
  nonisolated static func == (lhs: FakeAVPlayer, rhs: FakeAVPlayer) -> Bool {
    lhs.id == rhs.id
  }

  @DynamicInjected(\.notifier) private var notifier

  private static let log = Log.as("FakeAVPlayer")

  // MARK: - Helper Classes

  struct TimeObserver: Sendable {
    let interval: CMTime
    let queue: dispatch_queue_t?
    let block: @Sendable (CMTime) -> Void
  }

  struct ObservationHandler<T>: Sendable {
    weak var observation: NSKeyValueObservation?
    let handler: @Sendable (T) -> Void
  }

  // MARK: - State Management

  var seekHandler: (CMTime) async -> Bool = { _ in (true) }
  var rateObservations: [ObservationHandler<Float>] = []
  var statusObservations: [ObservationHandler<AVPlayer.TimeControlStatus>] = []
  var timeObservers: [UUID: TimeObserver] = [:]
  var currentTimeValue: CMTime = .zero {
    didSet {
      let currentTimeValue = currentTimeValue
      for observer in timeObservers.values {
        if let queue = observer.queue {
          queue.async {
            observer.block(currentTimeValue)
          }
        } else {
          observer.block(currentTimeValue)
        }
      }
    }
  }

  // MARK: - AVPlayable Current

  private(set) var current: (any AVPlayableItem)? {
    didSet {
      Self.log.debug("didSet current to: \(String(describing: current))")

      if current == nil {
        timeControlStatus = .paused
      } else if timeControlStatus == .waitingToPlayAtSpecifiedRate {
        timeControlStatus = .playing
        setRate(defaultRate)
      }
      // else: (paused stays paused, playing stays playing if replacing items)
    }
  }

  func replaceCurrent(with item: (any AVPlayableItem)?) {
    current = item
  }

  // MARK: - AVPlayable Playback

  func play() {
    if current == nil {
      timeControlStatus = .waitingToPlayAtSpecifiedRate
    } else {
      timeControlStatus = .playing
      setRate(defaultRate)
    }
  }

  func pause() {
    timeControlStatus = .paused
    setRate(0.0)
  }

  func seek(to time: CMTime, completionHandler: @escaping @Sendable (Bool) -> Void) {
    Task { [weak self] in
      guard let self else { return }
      let success = await seekHandler(time)
      completionHandler(success)
      if success { currentTimeValue = time }
    }
  }

  private var _defaultRate: Float = 1.0
  var defaultRate: Float { _defaultRate }
  func setDefaultRate(_ defaultRate: Float) {
    _defaultRate = defaultRate
  }
  private var _rate: Float = 0.0
  var rate: Float { _rate }
  func setRate(_ rate: Float) {
    Self.log.debug("setRate: \(rate)")

    _rate = rate

    // Clean up deallocated observations and call active handlers
    rateObservations = rateObservations.compactMap { observationHandler in
      guard observationHandler.observation != nil else { return nil }

      Self.log.debug("Calling active rate handler with: \(rate)")
      observationHandler.handler(rate)
      return observationHandler
    }
  }

  func observeRate(
    options: NSKeyValueObservingOptions,
    changeHandler: @Sendable @escaping (Float) -> Void
  ) -> NSKeyValueObservation {
    let observation = NSObject().observe(\.description, options: []) { _, _ in }
    rateObservations.append(ObservationHandler(observation: observation, handler: changeHandler))

    if options.contains(.initial) {
      changeHandler(rate)
    }

    return observation
  }

  // MARK: - AVPlayable Time

  func currentTime() -> CMTime { currentTimeValue }
  func addPeriodicTimeObserver(
    forInterval interval: CMTime,
    queue: dispatch_queue_t?,
    using block: @escaping @Sendable (CMTime) -> Void
  ) -> Any {
    let id = UUID()
    timeObservers[id] = TimeObserver(interval: interval, queue: queue, block: block)
    return id
  }

  func removeTimeObserver(_ observer: Any) {
    guard let id = observer as? UUID
    else { Assert.fatal("Removing time observer: \(observer), of wrong type?") }

    timeObservers[id] = nil
  }

  // MARK: - AVPlayable Status

  private(set) var timeControlStatus: AVPlayer.TimeControlStatus = .paused {
    didSet {
      Self.log.debug("didSet timeControlStatus to: \(timeControlStatus)")

      // Clean up deallocated observations and call active handlers
      statusObservations = statusObservations.compactMap { observationHandler in
        guard observationHandler.observation != nil else { return nil }

        Self.log.debug("Calling active timeControlStatus handler with: \(timeControlStatus)")
        observationHandler.handler(timeControlStatus)
        return observationHandler
      }
    }
  }
  func observeTimeControlStatus(
    options: NSKeyValueObservingOptions,
    changeHandler: @escaping @Sendable (AVPlayer.TimeControlStatus) -> Void
  ) -> NSKeyValueObservation {
    let observation = NSObject().observe(\.description, options: []) { _, _ in }
    statusObservations.append(ObservationHandler(observation: observation, handler: changeHandler))

    if options.contains(.initial) {
      changeHandler(timeControlStatus)
    }

    return observation
  }

  private(set) var reasonForWaitingToPlay: AVPlayer.WaitingReason?

  // MARK: - Testing Manipulators

  func finishEpisode() {
    Assert.precondition(timeControlStatus == .playing, "Can't finish an episode not playing!")

    guard let current
    else { Assert.fatal("Can't finish an episode that doesn't exist!") }

    Self.log.debug("finishEpisode: \(current)")

    timeControlStatus = .paused

    notifier.continuation(for: AVPlayerItem.didPlayToEndTimeNotification)
      .yield(
        Notification(
          name: AVPlayerItem.didPlayToEndTimeNotification,
          object: current
        )
      )
  }

  func advanceTime(to cmTime: CMTime) {
    currentTimeValue = cmTime
  }

  func waitingToPlay(waitingReason: AVPlayer.WaitingReason? = nil) {
    reasonForWaitingToPlay = waitingReason
    timeControlStatus = .waitingToPlayAtSpecifiedRate
  }
}
