// Copyright Justin Bishop, 2026

import Foundation

// Rolling FIFO of recent successful rebuild durations, used to size the
// recommendation engine's cache and recommendations debounce windows.
//
// The shape of the rule is `max(window) * safetyMultiplier`, clamped to
// `[minimumDebounce, maximumDebounce]`. Taking the rolling max (rather than
// mean) means one slow outlier raises the bar immediately; capping the window
// at `capacity` entries means it ages out after `capacity` later completions
// instead of getting stuck high.
//
// Persisting the window across launches lets a slow outlier observed in one
// session survive until later sessions push it out, preventing both
// "stuck high forever" and "every cold launch starts over."
//
// Cancelled or failed passes do not record; only the success path appends.
// Otherwise a pass cancelled by `.background` would lie about its work cost.
struct AdaptiveDebounceWindow: Codable, Sendable, Equatable, DefaultsStorable {
  static let capacity = 5
  static let minimumDebounce: Duration = .seconds(1)
  static let maximumDebounce: Duration = .seconds(120)
  static let safetyMultiplier: Double = 2.0

  // Newest entry first; trimmed to `capacity`.
  private let durations: [Duration]

  init() { self.init(durations: []) }

  private init(durations: [Duration]) {
    self.durations = durations
  }

  func recording(_ duration: Duration) -> Self {
    var updated = [duration] + durations
    if updated.count > Self.capacity {
      updated.removeLast(updated.count - Self.capacity)
    }
    return Self(durations: updated)
  }

  // `cappedFrom` is non-nil only when the safety-multiplied max would have
  // exceeded `maximumDebounce`; callers can surface a warning so a real
  // cap-hit shows up in Sentry as a signal worth investigating.
  func currentDebounce() -> (duration: Duration, cappedFrom: Duration?) {
    guard let worst = durations.max() else {
      return (Self.minimumDebounce, nil)
    }
    let scaled = worst * Self.safetyMultiplier
    if scaled > Self.maximumDebounce {
      return (Self.maximumDebounce, scaled)
    }
    if scaled < Self.minimumDebounce {
      return (Self.minimumDebounce, nil)
    }
    return (scaled, nil)
  }
}
