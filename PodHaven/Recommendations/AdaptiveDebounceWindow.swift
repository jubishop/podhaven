// Copyright Justin Bishop, 2026

import Foundation

// Sizing rules for the recommendation engine's adaptive cache and
// recommendations debounce windows. The window itself is stored on the
// engine as a plain persisted `[Duration]` (newest entry first); this
// namespace owns the rules that operate on that array.
//
// The shape is `max(window) * safetyMultiplier`, clamped to
// `[minimumDebounce, maximumDebounce]`. Taking the rolling max (not mean)
// means one slow outlier raises the bar immediately; capping the window at
// `capacity` entries means it ages out after `capacity` later completions
// instead of getting stuck high.
//
// Cancelled or failed passes must not be recorded — only the success path
// appends. A `.background`-cancelled pass would otherwise lie about its
// work cost and falsely shrink the window.
enum AdaptiveDebounceWindow {
  static let capacity = 5
  static let minimumDebounce: Duration = .seconds(1)
  static let maximumDebounce: Duration = .seconds(120)
  static let safetyMultiplier: Double = 2.0

  // Returns the window with `duration` prepended, trimmed to `capacity`.
  static func recording(_ duration: Duration, into window: [Duration]) -> [Duration] {
    var updated = [duration] + window
    if updated.count > capacity {
      updated.removeLast(updated.count - capacity)
    }
    return updated
  }

  // `cappedFrom` is non-nil only when the safety-multiplied max would have
  // exceeded `maximumDebounce`; callers surface a warning so a real cap-hit
  // shows up in Sentry as a signal worth investigating.
  static func currentDebounce(for window: [Duration])
    -> (duration: Duration, cappedFrom: Duration?)
  {
    guard let worst = window.max() else {
      return (minimumDebounce, nil)
    }
    let scaled = worst * safetyMultiplier
    if scaled > maximumDebounce {
      return (maximumDebounce, scaled)
    }
    if scaled < minimumDebounce {
      return (minimumDebounce, nil)
    }
    return (scaled, nil)
  }
}
