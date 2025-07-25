// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation

@testable import PodHaven

class FakeAVQueuePlayer: AVQueuePlayable {
  @DynamicInjected(\.notifier) private var notifier

  private static let log = Log.as("FakeAVQueuePlayer")

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

  struct MainActorObservationHandler<T>: Sendable {
    weak var observation: NSKeyValueObservation?
    let handler: @MainActor (T) -> Void
  }

  // MARK: - State Management

  var currentItemObservations: [MainActorObservationHandler<(any AVPlayableItem)?>] = []
  var seekHandler: (CMTime) async -> Bool = { _ in (true) }
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

  // MARK: - AVQueuePlayable Queue

  var queued: [any AVPlayableItem] = [] {
    didSet {
      Self.log.debug("didSet queued to: \(queued)")

      if oldValue.first !== current {
        // Clean up deallocated observations and call active handlers
        currentItemObservations = currentItemObservations.compactMap { observationHandler in
          guard observationHandler.observation != nil else { return nil }

          Self.log.debug("Calling active currentItem handler with: \(String(describing: current))")
          Task { @MainActor in observationHandler.handler(current) }
          return observationHandler
        }
      }
      if queued.isEmpty { timeControlStatus = .paused }
    }
  }

  func insert(_ item: any AVPlayableItem, after afterItem: (any AVPlayableItem)?) {
    if let afterItem {
      guard let afterIndex = queued.firstIndex(where: { $0.episodeID == afterItem.episodeID })
      else { Assert.fatal("Couldn't find item: \(afterItem), to insert after!") }

      queued.insert(item, at: afterIndex + 1)
    } else {
      if let existingItem = queued.first(where: { $0.episodeID == item.episodeID }) {
        Assert.fatal("Item: \(existingItem), already exists in queue!")
      }

      queued.append(item)
    }
  }

  func remove(_ item: any AVPlayableItem) {
    if !queued.contains(where: { $0.episodeID == item.episodeID }) {
      Assert.fatal("Item: \(item), does not exist in queue!")
    }

    queued.removeAll { $0.episodeID == item.episodeID }
  }

  func removeAllItems() {
    queued.removeAll()
  }

  // MARK: - AVQueuePlayable Current

  var current: (any AVPlayableItem)? { queued.first }
  func observeCurrentItem(
    options: NSKeyValueObservingOptions,
    changeHandler: @escaping @MainActor ((any AVPlayableItem)?) -> Void
  ) -> NSKeyValueObservation {
    let observation = NSObject().observe(\.description, options: []) { _, _ in }
    currentItemObservations.append(
      MainActorObservationHandler(observation: observation, handler: changeHandler)
    )

    if options.contains(.initial) {
      Task { @MainActor in changeHandler(current) }
    }

    return observation
  }

  // MARK: - AVQueuePlayable Playback

  func play() {
    timeControlStatus = .playing
  }

  func pause() {
    timeControlStatus = .paused
  }

  func seek(to time: CMTime, completionHandler: @escaping @Sendable (Bool) -> Void) {
    Task {
      let success = await seekHandler(time)
      completionHandler(success)
      if success { currentTimeValue = time }
    }
  }

  func observeRate(
    options: NSKeyValueObservingOptions,
    changeHandler: @Sendable @escaping (Float) -> Void
  ) -> NSKeyValueObservation {
    NSObject().observe(\.description, options: []) { _, _ in }
  }

  // MARK: - AVQueuePlayable Time

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

  // MARK: - AVQueuePlayable Status

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

  private(set) var reasonForWaitingToPlay: AVPlayer.WaitingReason?
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

  // MARK: - Testing Manipulators

  @discardableResult
  private func assertEpisodeCanFinish() -> any AVPlayableItem {
    Assert.precondition(
      timeControlStatus == .playing,
      "Can't simulate finishing episode when not playing!"
    )

    guard let currentItem = queued.first
    else { Assert.fatal("Can't finish an episode that doesn't exist!") }

    return currentItem
  }

  func triggerDidPlayToEnd() {
    let currentItem = assertEpisodeCanFinish()
    Self.log.debug("triggerDidPlayToEnd: \(String(describing: currentItem.episodeID))")

    notifier.continuation(for: AVPlayerItem.didPlayToEndTimeNotification)
      .yield(
        Notification(
          name: AVPlayerItem.didPlayToEndTimeNotification,
          object: FakeAVPlayerItem(episodeID: currentItem.episodeID)
        )
      )
  }

  func advanceCurrentItem() {
    let currentItem = assertEpisodeCanFinish()
    Self.log.debug("advanceCurrentItem: \(String(describing: currentItem.episodeID))")

    queued.removeFirst()
  }

  func finishEpisode() {
    triggerDidPlayToEnd()
    advanceCurrentItem()
  }

  func advanceTime(to cmTime: CMTime) {
    currentTimeValue = cmTime
  }

  func waitingToPlay(waitingReason: AVPlayer.WaitingReason? = nil) {
    Assert.precondition(
      timeControlStatus == .playing,
      "Can only simulate waitingToPlay if playing!"
    )

    reasonForWaitingToPlay = waitingReason
    timeControlStatus = .waitingToPlayAtSpecifiedRate
  }
}
