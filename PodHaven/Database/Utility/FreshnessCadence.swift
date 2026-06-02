// Copyright Justin Bishop, 2026

import Foundation
import GRDB

// Stored on Podcast as Optional — `nil` means "auto", resolved lazily via
// `infer(from:now:)` against the show's episode pubDates.
enum FreshnessCadence: String, Codable, DatabaseValueConvertible, Sendable, CaseIterable {
  case hourly
  case twiceDaily
  case daily
  case twiceWeekly
  case weekly
  case monthly
  case evergreen

  static let `default`: FreshnessCadence = .weekly

  // Cap on samples used by `infer`. Median-gap inference is stable well
  // before this many samples, so we ignore older history; this also lets
  // callers (e.g. the Observatory's SQL window query) bound their fetch to
  // the same window without diverging from in-memory callers.
  static let inferenceMaxSamples = 100

  // Past this long without a new episode, treat the show as evergreen
  // regardless of historical spacing — catches wrapped-up serials and
  // archives where freshness is meaningless even if the median gap was weekly.
  private static let dormantThresholdHours: Double = 120 * 24

  // Upper bounds on the *median* inter-episode gap, in hours. Each ceiling
  // sits far enough above its cadence's nominal publish period that a show
  // publishing at that cadence lands inside its own band despite jitter.
  private static let hourlyMaxMedianHours: Double = 3
  private static let twiceDailyMaxMedianHours: Double = 16
  private static let dailyMaxMedianHours: Double = 36
  private static let twiceWeeklyMaxMedianHours: Double = 126
  private static let weeklyMaxMedianHours: Double = 252
  private static let monthlyMaxMedianHours: Double = 1080

  var displayName: String {
    switch self {
    case .hourly: "Hourly"
    case .twiceDaily: "Twice Daily"
    case .daily: "Daily"
    case .twiceWeekly: "Twice Weekly"
    case .weekly: "Weekly"
    case .monthly: "Monthly"
    case .evergreen: "Evergreen"
    }
  }

  // Half-life for FreshnessSignal's hyperbolic decay, in hours. Evergreen returns nil — no decay.
  var halfLifeHours: Int? {
    switch self {
    case .hourly: 3
    case .twiceDaily: 16
    case .daily: 36
    case .twiceWeekly: 126
    case .weekly: 252
    case .monthly: 1080
    case .evergreen: nil
    }
  }

  static func infer(from pubDates: [Date], now: Date = Date()) -> FreshnessCadence {
    guard pubDates.count >= 3 else { return .default }

    let sorted = Array(pubDates.sorted().suffix(inferenceMaxSamples))
    guard let mostRecent = sorted.last else { return .default }
    if now.timeIntervalSince(mostRecent) > dormantThresholdHours * 3600 {
      return .evergreen
    }

    var gaps = [Double](capacity: sorted.count - 1)
    for index in 1..<sorted.count {
      gaps.append(sorted[index].timeIntervalSince(sorted[index - 1]) / 3600)
    }
    gaps.sort()
    let medianHours = gaps[gaps.count / 2]

    if medianHours <= hourlyMaxMedianHours { return .hourly }
    if medianHours <= twiceDailyMaxMedianHours { return .twiceDaily }
    if medianHours <= dailyMaxMedianHours { return .daily }
    if medianHours <= twiceWeeklyMaxMedianHours { return .twiceWeekly }
    if medianHours <= weeklyMaxMedianHours { return .weekly }
    if medianHours <= monthlyMaxMedianHours { return .monthly }
    return .evergreen
  }
}
