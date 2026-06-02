// Copyright Justin Bishop, 2026

import Foundation

// `inPlateau` gates the `.recentlyPublished` reason — true only inside the
// cadence-period grace window, so evergreen (no plateau) never surfaces it.
struct FreshnessSignal: Sendable, Equatable {
  let multiplier: Float
  let inPlateau: Bool

  // Flat 1.0 inside the cadence's grace window (a 6-day-old weekly isn't
  // stale yet), then `1 / (1 + (age - halfLife) / halfLife)` — a 21-day-old
  // weekly hits 0.5. Computed in hours so sub-daily cadences (hourly,
  // twiceDaily) decay on their own timescale. Evergreen has no half-life and
  // stays at 1.0.
  static func compute(
    pubDate: Date,
    cadence: FreshnessCadence,
    now: Date
  ) -> FreshnessSignal {
    guard let halfLifeHours = cadence.halfLifeHours else {
      return FreshnessSignal(multiplier: 1.0, inPlateau: false)
    }
    let hoursSince = now.timeIntervalSince(pubDate) / 3600
    let ageBeyondCadence = hoursSince - Double(halfLifeHours)
    guard ageBeyondCadence > 0 else {
      return FreshnessSignal(multiplier: 1.0, inPlateau: true)
    }
    let multiplier = Float(1.0 / (1.0 + ageBeyondCadence / Double(halfLifeHours)))
    return FreshnessSignal(multiplier: multiplier, inPlateau: false)
  }
}
