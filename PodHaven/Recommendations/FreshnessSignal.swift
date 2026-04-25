// Copyright Justin Bishop, 2026

import Foundation

// Captures both halves of the freshness signal RecommendationEngine applies
// to a candidate: the multiplier folded into the base score, and whether the
// episode is sitting in its podcast's cadence plateau (the only state that
// surfaces `.recentlyPublished`). Evergreen never sets `inPlateau` — it has
// no plateau, the user has opted out of treating freshness as a signal.
struct FreshnessSignal: Sendable, Equatable {
  let multiplier: Float
  let inPlateau: Bool

  // Hyperbolic decay with a flat plateau for one cadence period:
  // `1 / (1 + (age - cadence) / halfLife)` past the plateau, 1.0 inside it.
  // The plateau means an episode published within its own cadence is still
  // 100% fresh — a 6-day-old weekly episode shouldn't be dinged just for
  // being 6 days old when the next one hasn't dropped yet. Past the plateau,
  // decay is identical to the raw curve with `halfLife = cadenceDays` (an
  // 8-day weekly behaves like a 1-day-old under raw decay; a 14-day weekly
  // hits the 0.5 midpoint).
  static func compute(
    pubDate: Date,
    cadence: FreshnessCadence,
    now: Date
  ) -> FreshnessSignal {
    guard let halfLife = cadence.halfLifeDays else {
      return FreshnessSignal(multiplier: 1.0, inPlateau: false)
    }
    let daysSince = now.timeIntervalSince(pubDate) / 86400
    let ageBeyondCadence = daysSince - Double(halfLife)
    guard ageBeyondCadence > 0 else {
      return FreshnessSignal(multiplier: 1.0, inPlateau: true)
    }
    let multiplier = Float(1.0 / (1.0 + ageBeyondCadence / Double(halfLife)))
    return FreshnessSignal(multiplier: multiplier, inPlateau: false)
  }
}
