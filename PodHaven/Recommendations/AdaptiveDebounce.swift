// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging

// A `Debounce` whose sleep duration self-tunes to the cost of the work it
// debounces. The window of recent successful pass durations is persisted
// under a name-derived key so a slow outlier observed in one session
// survives across launches until later sessions push it out.
//
// Owners construct one per workstream (e.g. cache rebuild, recommendations
// rebuild), call it like a `Debounce`, and record the duration of each
// successful pass via `recordCompletedPass`. Failed or cancelled passes
// must not be recorded — they would falsely shrink the window.
//
// The sizing rule is `max(window) * safetyMultiplier`, clamped to
// `[minimumDuration, maximumDuration]`. A computation that hits the upper
// cap logs at `.warning` so a real cap-hit shows up in Sentry as a signal
// worth investigating.
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

  // Append a successful pass's measured duration to the window so the next
  // call sizes its debounce against it. Trims the FIFO to `capacity` so a
  // slow outlier ages out naturally instead of getting stuck high.
  func recordCompletedPass(_ duration: Duration) {
    var updated = [duration] + persistedWindow.wrappedValue
    if updated.count > capacity {
      updated.removeLast(updated.count - capacity)
    }
    persistedWindow.wrappedValue = updated
  }

  func cancel() { debounce.cancel() }

  var hasInFlightTask: Bool { debounce.hasInFlightTask }

  func callAsFunction(_ action: @escaping @Sendable () async -> Void) {
    debounce.duration = currentDuration()
    debounce(action)
  }

  // Reads the window, applies the safety multiplier, surfaces any cap hit,
  // and clamps to `[minimumDuration, maximumDuration]`.
  private func currentDuration() -> Duration {
    let window = persistedWindow.wrappedValue
    let scaled: Duration
    guard let worst = window.max() else {
      return minimumDuration
    }
    scaled = worst * safetyMultiplier
    if scaled > maximumDuration {
      log.warning(
        """
        Hit \(maximumDuration) cap; window max × \(safetyMultiplier) was \
        \(scaled). Investigate whether a pass legitimately took this long.
        """
      )
      return maximumDuration
    }
    if scaled < minimumDuration { return minimumDuration }
    return scaled
  }
}
