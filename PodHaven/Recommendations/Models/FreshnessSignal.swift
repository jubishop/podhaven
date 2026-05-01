// Copyright Justin Bishop, 2026

import Foundation

// `inPlateau` gates the `.recentlyPublished` reason — true only inside the
// cadence-period grace window, so evergreen (no plateau) never surfaces it.
struct FreshnessSignal: Sendable, Equatable {
  let multiplier: Float
  let inPlateau: Bool

  // Flat 1.0 inside one cadence period (a 6-day-old weekly isn't stale yet),
  // then `1 / (1 + (age - cadence) / halfLife)` — a 14-day-old weekly hits 0.5.
  // Evergreen has no half-life and stays at 1.0.
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
