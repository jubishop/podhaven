// Copyright Justin Bishop, 2026

import Foundation

// `inPlateau` gates the `.recentlyPublished` reason — true only inside the
// cadence-period grace window, so evergreen (no plateau) never surfaces it.
struct FreshnessSignal: Sendable, Equatable {
  let multiplier: Float
  let inPlateau: Bool

  // Flat 1.0 while age is within the cadence's half-life (the grace window),
  // then `1 / (1 + (age - halfLife) / halfLife)`, so freshness reaches 0.5 at
  // twice the half-life and keeps decaying hyperbolically. Computed in hours so
  // sub-daily cadences decay on their own timescale. Evergreen has no half-life
  // and stays at 1.0.
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
