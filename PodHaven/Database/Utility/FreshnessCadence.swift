// Copyright Justin Bishop, 2026

import Foundation
import GRDB

// Stored on Podcast as Optional — `nil` means "auto", resolved lazily via
// `infer(from:now:)` against the show's episode pubDates.
enum FreshnessCadence: String, Codable, DatabaseValueConvertible, Sendable, CaseIterable {
  case daily
  case weekly
  case monthly
  case evergreen

  static let `default`: FreshnessCadence = .weekly

  // Cap on samples used by `infer`. Median-gap inference is stable well
  // before this many samples, so we ignore older history; this also lets
  // callers (e.g. the Observatory's SQL window query) bound their fetch to
  // the same window without diverging from in-memory callers.
  static let inferenceMaxSamples = 100

  // Past this many days without a new episode, treat the show as evergreen
  // regardless of historical spacing — catches wrapped-up serials and
  // archives where freshness is meaningless even if the median gap was weekly.
  private static let dormantThresholdDays: Double = 120

  // Upper bounds on the *median* inter-episode gap. Daily news shows publish
  // weekdays only (1d median with 3d weekend gaps), so 3d tolerates that.
  // Past ~48d, freshness is immaterial → evergreen.
  private static let dailyMaxMedianDays: Double = 2
  private static let weeklyMaxMedianDays: Double = 14
  private static let monthlyMaxMedianDays: Double = 60

  var displayName: String {
    switch self {
    case .daily: "Daily"
    case .weekly: "Weekly"
    case .monthly: "Monthly"
    case .evergreen: "Evergreen"
    }
  }

  // Half-life for FreshnessSignal's hyperbolic decay. Matches the cadence's
  // natural period so an episode one full period overdue (e.g. a 14-day-old
  // weekly) lands on the 0.5 midpoint. .evergreen returns nil — no decay.
  var halfLifeDays: Int? {
    switch self {
    case .daily: 1
    case .weekly: 7
    case .monthly: 30
    case .evergreen: nil
    }
  }

  static func infer(from pubDates: [Date], now: Date = Date()) -> FreshnessCadence {
    guard pubDates.count >= 3 else { return .default }

    let sorted = Array(pubDates.sorted().suffix(inferenceMaxSamples))
    guard let mostRecent = sorted.last else { return .default }
    if now.timeIntervalSince(mostRecent) > dormantThresholdDays * 86400 {
      return .evergreen
    }

    var gaps = [Double](capacity: sorted.count - 1)
    for index in 1..<sorted.count {
      gaps.append(sorted[index].timeIntervalSince(sorted[index - 1]) / 86400)
    }
    gaps.sort()
    let medianDays = gaps[gaps.count / 2]

    if medianDays <= dailyMaxMedianDays { return .daily }
    if medianDays <= weeklyMaxMedianDays { return .weekly }
    if medianDays <= monthlyMaxMedianDays { return .monthly }
    return .evergreen
  }
}
