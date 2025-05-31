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
    private weak var player: FakeAVQueuePlayer?
    
    init(player: FakeAVQueuePlayer) {
      self.player = player
      super.init()
    }
  }
  
  // MARK: - AVQueuePlayable Implementation
  
  func addPeriodicTimeObserver(
    forInterval interval: CMTime,
    queue: dispatch_queue_t?,
    using block: @escaping @Sendable (CMTime) -> Void
  ) -> Any {
    let observer = TimeObserver(interval: interval, queue: queue, block: block)
    timeObservers.append(observer)
    return observer.id
  }
  
  func currentTime() -> CMTime {
    return currentTimeValue
  }
  
  func insert(_ item: any AVPlayableItem, after afterItem: (any AVPlayableItem)?) {
    if let afterItem = afterItem,
       let afterIndex = queueItems.firstIndex(where: { $0.assetURL == afterItem.assetURL }) {
      queueItems.insert(item, at: afterIndex + 1)
    } else {
      queueItems.append(item)
    }
  }
  
  func items() -> [any AVPlayableItem] {
    return queueItems
  }
  
  func pause() {
    isPlaying = false
    setTimeControlStatus(.paused)
  }
  
  func play() {
    isPlaying = true
    setTimeControlStatus(.playing)
  }
  
  func remove(_ item: any AVPlayableItem) {
    queueItems.removeAll { $0.assetURL == item.assetURL }
  }
  
  func removeAllItems() {
    queueItems.removeAll()
    isPlaying = false
    setTimeControlStatus(.paused)
  }
  
  func removeTimeObserver(_ observer: Any) {
    guard let observerId = observer as? UUID else { return }
    timeObservers.removeAll { $0.id == observerId }
  }
  
  func seek(to time: CMTime, completionHandler: @escaping @Sendable (Bool) -> Void) {
    currentTimeValue = time
    completionHandler(true)
  }
  
  func observeTimeControlStatus(
    options: NSKeyValueObservingOptions,
    changeHandler: @escaping @Sendable (AVPlayer.TimeControlStatus) -> Void
  ) -> NSKeyValueObservation {
    let observation = FakeObservation(player: self)
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
        queue.async {
          observer.block(currentTimeValue)
        }
      } else {
        observer.block(currentTimeValue)
      }
    }
  }
  
  func simulateTimeAdvancement(by interval: TimeInterval) {
    let newTime = CMTimeAdd(currentTimeValue, CMTime(seconds: interval, preferredTimescale: 1000))
    currentTimeValue = newTime
    triggerTimeObservers()
  }
  
  func setTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
    timeControlStatus = status
    for handler in statusHandlers.values {
      handler(status)
    }
  }
  
  func simulateBuffering() {
    setTimeControlStatus(.waitingToPlayAtSpecifiedRate)
  }
}
