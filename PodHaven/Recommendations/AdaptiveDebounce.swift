// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging

struct AdaptiveDebounce: Sendable {
  let capacity: Int
  let minimumDuration: Duration
  let maximumDuration: Duration
  let safetyMultiplier: Double

  private let debounce: Debounce
  private let persistedWindow: PersistedThreadSafe<[Duration]>
  private let log: Logger

  init(
    name: String,
    priority: TaskPriority? = nil,
    capacity: Int = 5,
    minimumDuration: Duration = .seconds(1),
    maximumDuration: Duration = .seconds(120),
    safetyMultiplier: Double = 2.0
  ) {
    self.capacity = capacity
    self.minimumDuration = minimumDuration
    self.maximumDuration = maximumDuration
    self.safetyMultiplier = safetyMultiplier
    self.debounce = Debounce(duration: minimumDuration, priority: priority)
    self.persistedWindow = PersistedThreadSafe(
      wrappedValue: [Duration](),
      "adaptiveDebounce.\(name).passDurations"
    )
    self.log = Log.as("AdaptiveDebounce.\(name)")
  }

  var passDurations: [Duration] { persistedWindow.wrappedValue }
  var hasInFlightTask: Bool { debounce.hasInFlightTask }

  // Only success-path calls — cancelled/failed passes would falsely shrink
  // the window.
  func recordCompletedPass(_ duration: Duration) {
    var updated = [duration] + persistedWindow.wrappedValue
    if updated.count > capacity {
      updated.removeLast(updated.count - capacity)
    }
    persistedWindow.wrappedValue = updated
  }

  func cancel() { debounce.cancel() }

  func callAsFunction(_ action: @escaping @Sendable () async -> Void) {
    let (duration, cappedFrom) = computeDebounce()
    if let cappedFrom {
      log.warning(
        "Hit \(maximumDuration) cap; window max × \(safetyMultiplier) was \(cappedFrom)."
      )
    }
    debounce.duration = duration
    debounce(action)
  }

  private func computeDebounce() -> (duration: Duration, cappedFrom: Duration?) {
    guard let worst = persistedWindow.wrappedValue.max() else {
      return (minimumDuration, nil)
    }
    let scaled = worst * safetyMultiplier
    if scaled > maximumDuration { return (maximumDuration, scaled) }
    if scaled < minimumDuration { return (minimumDuration, nil) }
    return (scaled, nil)
  }
}
