// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

@testable import PodHaven

class FakeAVQueuePlayer: AVQueuePlayable {
  // MARK: - Public State for Testing

  private(set) var isPlaying: Bool = false
  private(set) var currentTimeValue: CMTime = .zero
  private(set) var timeControlStatus: AVPlayer.TimeControlStatus = .paused
  private(set) var queueItems: [any AVPlayableItem] = []
  var seekCompletion: Bool = true

  // MARK: - Internal Storage

  private var timeObservers: [TimeObserver] = []
  private var statusHandlers: [UUID: (AVPlayer.TimeControlStatus) -> Void] = [:]

  // MARK: - Helper Classes

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

  private class FakeObservation: NSObject {
    let id = UUID()
  }

  // MARK: - AVQueuePlayable Implementation

  private(set) var reasonForWaitingToPlay: AVPlayer.WaitingReason?

  func currentTime() -> CMTime { currentTimeValue }

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

  func items() -> [any AVPlayableItem] { queueItems }

  func pause() {
    isPlaying = false
    setTimeControlStatus(.paused)
  }

  func play() {
    isPlaying = true
    setTimeControlStatus(.playing)
  }

  func remove(_ item: any AVPlayableItem) {
    if !queueItems.contains(where: { $0.assetURL == item.assetURL }) {
      Assert.fatal("Item: \(item), does not exist in queue!")
    }

    queueItems.removeAll { $0.assetURL == item.assetURL }
  }

  func removeAllItems() {
    queueItems.removeAll()
    isPlaying = false
    setTimeControlStatus(.paused)
  }

  func removeTimeObserver(_ observer: Any) {
    guard let observerId = observer as? UUID
    else { Assert.fatal("Removing time observer: \(observer), of wrong type?") }

    timeObservers.removeAll { $0.id == observerId }
  }

  func seek(to time: CMTime, completionHandler: @escaping @Sendable (Bool) -> Void) {
    currentTimeValue = time
    completionHandler(seekCompletion)
  }

  func addPeriodicTimeObserver(
    forInterval interval: CMTime,
    queue: dispatch_queue_t?,
    using block: @escaping @Sendable (CMTime) -> Void
  ) -> Any {
    let observer = TimeObserver(interval: interval, queue: queue, block: block)
    timeObservers.append(observer)
    return observer.id
  }

  func observeTimeControlStatus(
    options: NSKeyValueObservingOptions,
    changeHandler: @escaping @Sendable (AVPlayer.TimeControlStatus) -> Void
  ) -> NSKeyValueObservation {
    let observation = FakeObservation()
    statusHandlers[observation.id] = changeHandler

    if options.contains(.initial) {
      changeHandler(timeControlStatus)
    }

    return observation.observe(\.description, options: []) { _, _ in }
  }

  // MARK: - Testing Helper Methods

  func triggerTimeObservers() {
    let currentTimeValue = self.currentTimeValue
    for observer in timeObservers {
      if let queue = observer.queue {
        queue.sync {
          observer.block(currentTimeValue)
        }
      } else {
        observer.block(currentTimeValue)
      }
    }
  }

  func simulateTimeAdvancement(by interval: TimeInterval) {
    let newTime = CMTimeAdd(currentTimeValue, CMTime.inSeconds(interval))
    currentTimeValue = newTime
    triggerTimeObservers()
  }

  func setTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
    timeControlStatus = status
    for handler in statusHandlers.values {
      handler(status)
    }
  }

  func simulateWaitingToPlay(waitingReason: AVPlayer.WaitingReason? = nil) {
    reasonForWaitingToPlay = waitingReason
    setTimeControlStatus(.waitingToPlayAtSpecifiedRate)
  }
}
