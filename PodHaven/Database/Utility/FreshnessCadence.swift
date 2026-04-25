// Copyright Justin Bishop, 2026

import Foundation
import GRDB

// How quickly a podcast's episodes lose freshness in the recommendation
// score, expressed as the show's natural publish cadence. RecommendationEngine
// translates each case to a half-life for its hyperbolic decay; .evergreen
// disables decay entirely (multiplier always 1.0). The Podcast row stores
// this as Optional — `nil` means "auto", and the engine resolves it lazily
// by inferring from the podcast's episode pubDates (see `infer(from:now:)`).
// `default` is the fallback used when there's no manual choice and not
// enough episodes for inference to be confident.
enum FreshnessCadence: String, Codable, DatabaseValueConvertible, Sendable, CaseIterable {
  case daily
  case weekly
  case monthly
  case evergreen

  // The fallback cadence used wherever a concrete cadence is needed but
  // none has been chosen and inference can't yield one (< 3 episodes).
  // Centralized here so Observatory/RecommendationEngine/UI all agree on
  // what "unset" resolves to without each owning the constant.
  static let `default`: FreshnessCadence = .weekly

  // A podcast that hasn't published in this long is treated as evergreen,
  // regardless of its historical cadence. Catches dormant/archive shows like
  // a wrapped-up serial — historical median gap might be weekly, but no new
  // episode is coming, so freshness is meaningless.
  private static let dormantThresholdDays: Double = 180

  // Boundaries on the *median* inter-episode gap, in days. Daily news shows
  // typically publish every weekday (median 1d, with 3d weekend gaps); 3d
  // tolerates that. Weekly podcasts cluster around 7d but allow some slop.
  // Anything wider than ~48d only really makes sense as monthly+; past that
  // we treat freshness as immaterial.
  private static let dailyMaxMedianDays: Double = 3
  private static let weeklyMaxMedianDays: Double = 12
  private static let monthlyMaxMedianDays: Double = 48

  // Human-readable picker / settings label.
  var displayName: String {
    switch self {
    case .daily: "Daily"
    case .weekly: "Weekly"
    case .monthly: "Monthly"
    case .evergreen: "Evergreen"
    }
  }

  // Half-life used by FreshnessSignal's hyperbolic decay past the plateau.
  // Each value matches the cadence's natural period so an episode that's one
  // full cadence-period overdue (e.g. a 14-day-old weekly) lands on the 0.5
  // midpoint of the curve. .evergreen returns nil — there is no decay, the
  // signal multiplier is always 1.0.
  var halfLifeDays: Int? {
    switch self {
    case .daily: 1
    case .weekly: 7
    case .monthly: 30
    case .evergreen: nil
    }
  }

  // Infer a cadence from a podcast's episode publish dates. Used by
  // RecommendationEngine to resolve podcasts whose stored cadence is nil,
  // and by PodcastSettingsView to render the "Auto" picker label. Falls
  // back to `.default` when there isn't enough data to be confident (< 3
  // episodes) since that's the most common cadence anyway.
  static func infer(from pubDates: [Date], now: Date = Date()) -> FreshnessCadence {
    guard pubDates.count >= 3 else { return .default }

    let sorted = pubDates.sorted()
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
