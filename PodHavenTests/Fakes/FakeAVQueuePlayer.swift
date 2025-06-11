// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation

@testable import PodHaven

class FakeAVQueuePlayer: AVQueuePlayable {
  @DynamicInjected(\.notifier) private var notifier

  // MARK: - Internal State Management

  var itemObservations: [ObservationHandler<MediaURL?>] = []
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
  var statusObservations: [ObservationHandler<AVPlayer.TimeControlStatus>] = []

  // MARK: - Private Helper Classes

  struct TimeObserver: Sendable {
    let interval: CMTime
    let queue: dispatch_queue_t?
    let block: @Sendable (CMTime) -> Void
  }

  struct ObservationHandler<T> {
    weak var observation: NSKeyValueObservation?
    let handler: (T) -> Void
  }

  // MARK: - AVQueuePlayable Implementation

  var current: (any AVPlayableItem)? { queued.first }
  var queued: [any AVPlayableItem] = [] {
    didSet {
      if oldValue.first !== current {
        // Clean up deallocated observations and call active handlers
        itemObservations = itemObservations.compactMap { observationHandler in
          guard observationHandler.observation != nil else { return nil }
          observationHandler.handler(current?.assetURL)
          return observationHandler
        }
      }
    }
  }
  func observeCurrentItem(
    options: NSKeyValueObservingOptions,
    changeHandler: @escaping @Sendable (MediaURL?) -> Void
  ) -> NSKeyValueObservation {
    let observation = NSObject().observe(\.description, options: []) { _, _ in }
    itemObservations.append(ObservationHandler(observation: observation, handler: changeHandler))

    if options.contains(.initial) {
      changeHandler(current?.assetURL)
    }

    return observation
  }

  func insert(_ item: any AVPlayableItem, after afterItem: (any AVPlayableItem)?) {
    if let afterItem {
      guard let afterIndex = queued.firstIndex(where: { $0.assetURL == afterItem.assetURL })
      else { Assert.fatal("Couldn't find item: \(afterItem), to insert after!") }

      queued.insert(item, at: afterIndex + 1)
    } else {
      if let existingItem = queued.first(where: { $0.assetURL == item.assetURL }) {
        Assert.fatal("Item: \(existingItem), already exists in queue!")
      }

      queued.append(item)
    }
  }

  func remove(_ item: any AVPlayableItem) {
    if !queued.contains(where: { $0.assetURL == item.assetURL }) {
      Assert.fatal("Item: \(item), does not exist in queue!")
    }

    queued.removeAll { $0.assetURL == item.assetURL }
  }

  func removeAllItems() {
    queued.removeAll()
    timeControlStatus = .paused
  }

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
      seekHandler = { _ in true }
    }
  }

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

  private(set) var timeControlStatus: AVPlayer.TimeControlStatus = .paused {
    didSet {
      // Clean up deallocated observations and call active handlers
      statusObservations = statusObservations.compactMap { observationHandler in
        guard observationHandler.observation != nil else { return nil }
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

  var seekHandler: (CMTime) async -> (Bool) = { _ in (true) }

  func simulateFinishingEpisode() {
    Assert.precondition(
      timeControlStatus == .playing,
      "Can't simulate finishing episode when not playing!"
    )

    guard let currentItem = queued.first else { return }

    notifier.continuation(for: AVPlayerItem.didPlayToEndTimeNotification)
      .yield(
        Notification(
          name: AVPlayerItem.didPlayToEndTimeNotification,
          object: FakeAVPlayerItem(assetURL: currentItem.assetURL)
        )
      )

    queued.removeFirst()
  }

  func simulateTimeAdvancement(to cmTime: CMTime) {
    currentTimeValue = cmTime
  }

  func simulateWaitingToPlay(waitingReason: AVPlayer.WaitingReason? = nil) {
    Assert.precondition(
      timeControlStatus == .playing,
      "Can only simulate waitingToPlay if playing!"
    )

    reasonForWaitingToPlay = waitingReason
    timeControlStatus = .waitingToPlayAtSpecifiedRate
  }
}
