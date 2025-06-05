// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

@testable import PodHaven

class FakeAVQueuePlayer: AVQueuePlayable {
  // MARK: - Testing Manipulators

  var seekDelay: Duration = .zero
  var seekCompletion: Bool = true

  // MARK: - Internal State Management

  private var currentTimeValue: CMTime = .zero
  private var queueItems: [any AVPlayableItem] = []
  private var timeObservers: [TimeObserver] = []
  private var statusObservations: [ObservationHandler] = []

  // MARK: - Private Helper Classes

  private final class TimeObserver: Sendable {
    let id = UUID()
    let interval: CMTime
    let queue: dispatch_queue_t?
    let block: @Sendable (CMTime) -> Void

    init(interval: CMTime, queue: dispatch_queue_t?, block: @Sendable @escaping (CMTime) -> Void) {
      self.interval = interval
      self.queue = queue
      self.block = block
    }
  }

  private struct ObservationHandler {
    weak var observation: NSKeyValueObservation?
    let handler: (AVPlayer.TimeControlStatus) -> Void
  }

  // MARK: - AVQueuePlayable Implementation

  var current: (any AVPlayableItem)? { queueItems.first }
  var queued: [any AVPlayableItem] { queueItems }

  func insert(_ item: any AVPlayableItem, after afterItem: (any AVPlayableItem)?) {
    if let afterItem {
      guard let afterIndex = queueItems.firstIndex(where: { $0.assetURL == afterItem.assetURL })
      else { Assert.fatal("Couldn't find item: \(afterItem), to insert after!") }

      queueItems.insert(item, at: afterIndex + 1)
    } else {
      if let existingItem = queueItems.first(where: { $0.assetURL == item.assetURL }) {
        Assert.fatal("Item: \(existingItem), already exists in queue!")
      }

      queueItems.append(item)
    }
  }

  func remove(_ item: any AVPlayableItem) {
    if !queueItems.contains(where: { $0.assetURL == item.assetURL }) {
      Assert.fatal("Item: \(item), does not exist in queue!")
    }

    queueItems.removeAll { $0.assetURL == item.assetURL }
  }

  func removeAllItems() {
    queueItems.removeAll()
    setTimeControlStatus(.paused)
  }

  func play() {
    setTimeControlStatus(.playing)
  }
  func pause() {
    setTimeControlStatus(.paused)
  }
  func seek(to time: CMTime, completionHandler: @escaping @Sendable (Bool) -> Void) {
    Task {
      try await Task.sleep(for: seekDelay)
      completionHandler(seekCompletion)
      if seekCompletion {
        currentTimeValue = time
        triggerTimeObservers()
      }
    }
  }

  func currentTime() -> CMTime { currentTimeValue }
  func addPeriodicTimeObserver(
    forInterval interval: CMTime,
    queue: dispatch_queue_t?,
    using block: @escaping @Sendable (CMTime) -> Void
  ) -> Any {
    let observer = TimeObserver(interval: interval, queue: queue, block: block)
    timeObservers.append(observer)
    return observer.id
  }
  func removeTimeObserver(_ observer: Any) {
    guard let observerId = observer as? UUID
    else { Assert.fatal("Removing time observer: \(observer), of wrong type?") }

    timeObservers.removeAll { $0.id == observerId }
  }

  private(set) var timeControlStatus: AVPlayer.TimeControlStatus = .paused
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

  // MARK: - Testing Helper Methods

  func simulateTimeAdvancement(by interval: TimeInterval) {
    let newTime = CMTimeAdd(currentTimeValue, CMTime.inSeconds(interval))
    currentTimeValue = newTime
    triggerTimeObservers()
  }

  func setTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
    timeControlStatus = status
    
    // Clean up deallocated observations and call active handlers
    statusObservations = statusObservations.compactMap { observationHandler in
      guard observationHandler.observation != nil else { return nil }
      observationHandler.handler(status)
      return observationHandler
    }
  }

  func simulateWaitingToPlay(waitingReason: AVPlayer.WaitingReason? = nil) {
    reasonForWaitingToPlay = waitingReason
    setTimeControlStatus(.waitingToPlayAtSpecifiedRate)
  }
  
  // MARK: - Private Helpers
  
  private func triggerTimeObservers() {
    let currentTimeValue = self.currentTimeValue
    for observer in timeObservers {
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
