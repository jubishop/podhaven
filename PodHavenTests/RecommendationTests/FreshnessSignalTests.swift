// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("FreshnessSignal decay tests")
struct FreshnessSignalTests {
  private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  private func signal(_ cadence: FreshnessCadence, hoursAgo: Double) -> FreshnessSignal {
    FreshnessSignal.compute(
      pubDate: now.addingTimeInterval(-hoursAgo * 3600),
      cadence: cadence,
      now: now
    )
  }

  @Test("evergreen never decays and never plateaus")
  func evergreenIsFlat() {
    let fresh = signal(.evergreen, hoursAgo: 1)
    let old = signal(.evergreen, hoursAgo: 10_000)
    #expect(fresh.multiplier == 1.0)
    #expect(old.multiplier == 1.0)
    #expect(!fresh.inPlateau)
    #expect(!old.inPlateau)
  }

  @Test("within the half-life window the signal stays at full strength and plateaus")
  func plateauHoldsFullStrength() {
    // hourly half-life is 2h: a 1h-old hourly episode is still in plateau.
    let signal = signal(.hourly, hoursAgo: 1)
    #expect(signal.multiplier == 1.0)
    #expect(signal.inPlateau)
  }

  @Test("hourly decays far faster than daily for the same absolute age")
  func hourlyOutdecaysDaily() {
    // 12 hours old: hourly (half-life 2h) is well past its window; daily
    // (half-life 48h) is still inside its plateau at full strength.
    let hourly = signal(.hourly, hoursAgo: 12)
    let daily = signal(.daily, hoursAgo: 12)
    #expect(daily.multiplier == 1.0)
    #expect(daily.inPlateau)
    #expect(hourly.multiplier < 0.5)
    #expect(!hourly.inPlateau)
  }

  @Test("decays to one half at twice the half-life past the plateau")
  func halfStrengthPastPlateau() {
    // hourly half-life is 2h: the plateau ends at 2h, and at 4h (one further
    // half-life) the multiplier is 1 / (1 + 2/2) = 0.5.
    let signal = signal(.hourly, hoursAgo: 4)
    #expect(abs(signal.multiplier - 0.5) < 0.0001)
  }

  @Test("twiceDaily and twiceWeekly sit between their neighbors")
  func intermediateCadencesOrderBetweenNeighbors() {
    // At 36h, twiceDaily (half-life 24h) has decayed while daily (48h) is
    // still plateaued.
    #expect(
      signal(.twiceDaily, hoursAgo: 36).multiplier < signal(.daily, hoursAgo: 36).multiplier
    )
    // At 10 days (240h), twiceWeekly (half-life 168h) has decayed while
    // weekly (336h) is still plateaued.
    #expect(
      signal(.twiceWeekly, hoursAgo: 240).multiplier < signal(.weekly, hoursAgo: 240).multiplier
    )
  }
}
