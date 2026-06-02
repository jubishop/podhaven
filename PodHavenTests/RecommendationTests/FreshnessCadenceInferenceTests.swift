// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("FreshnessCadence inference tests")
struct FreshnessCadenceInferenceTests {
  private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  private func dates(daysAgo: [Double]) -> [Date] {
    daysAgo.map { now.addingTimeInterval(-$0 * 86400) }
  }

  @Test("returns .weekly when there are fewer than 3 episodes")
  func fallsBackToWeeklyOnSparseInput() {
    #expect(FreshnessCadence.infer(from: [], now: now) == .weekly)
    #expect(FreshnessCadence.infer(from: dates(daysAgo: [0, 7]), now: now) == .weekly)
  }

  @Test("infers .hourly for shows publishing roughly every hour")
  func detectsHourlyCadence() {
    let hourly = stride(from: 0.0, to: 2.0, by: 1.0 / 24.0).map { $0 }
    #expect(FreshnessCadence.infer(from: dates(daysAgo: hourly), now: now) == .hourly)
  }

  @Test("infers .twiceDaily for shows publishing every ~12 hours")
  func detectsTwiceDailyCadence() {
    let twiceDaily = stride(from: 0.0, to: 7.0, by: 0.5).map { $0 }
    #expect(FreshnessCadence.infer(from: dates(daysAgo: twiceDaily), now: now) == .twiceDaily)
  }

  @Test("infers .daily for shows publishing roughly every day or two")
  func detectsDailyCadence() {
    // Daily band is (24h, 48h]: slower than once a day, up to once per two
    // days. A strict 24h cadence tips into .twiceDaily by design.
    let everyDayOrTwo = dates(daysAgo: stride(from: 0.0, to: 30, by: 1.5).map { $0 })
    #expect(FreshnessCadence.infer(from: everyDayOrTwo, now: now) == .daily)

    let aboutThirtyHours = dates(daysAgo: [0, 1.25, 2.5, 3.75, 5, 6.25])
    #expect(FreshnessCadence.infer(from: aboutThirtyHours, now: now) == .daily)
  }

  @Test("infers .weekly for shows publishing every 8-14 days")
  func detectsWeeklyCadence() {
    // Weekly band is (168h, 336h]: slower than once a week, up to once a
    // fortnight. A strict 7-day cadence tips into .twiceWeekly by design.
    let weeklyish = dates(daysAgo: stride(from: 0.0, to: 90, by: 9).map { $0 })
    #expect(FreshnessCadence.infer(from: weeklyish, now: now) == .weekly)

    let biweeklyish = dates(daysAgo: stride(from: 0.0, to: 90, by: 11).map { $0 })
    #expect(FreshnessCadence.infer(from: biweeklyish, now: now) == .weekly)
  }

  @Test("infers .twiceWeekly for shows publishing a couple times a week")
  func detectsTwiceWeeklyCadence() {
    // Monday/Thursday pattern: gaps alternate 3 and 4 days (median 4 days),
    // within the (2d, 7d] twiceWeekly band.
    let mondayThursday = dates(daysAgo: [0, 3, 7, 10, 14, 17, 21])
    #expect(FreshnessCadence.infer(from: mondayThursday, now: now) == .twiceWeekly)
  }

  @Test("infers .monthly for shows publishing every 13-60 days")
  func detectsMonthlyCadence() {
    let strictMonthly = dates(daysAgo: stride(from: 0.0, to: 360, by: 30).map { $0 })
    #expect(FreshnessCadence.infer(from: strictMonthly, now: now) == .monthly)
  }

  @Test("infers .evergreen for shows whose latest episode is older than 6 months")
  func detectsDormantAsEvergreen() {
    // Weekly cadence historically, but no new episodes in over a year — the
    // show is dormant or wrapped, freshness no longer matters.
    let dormant = dates(daysAgo: stride(from: 400.0, to: 500, by: 7).map { $0 })
    #expect(FreshnessCadence.infer(from: dormant, now: now) == .evergreen)
  }

  @Test("infers .evergreen for active shows with very long inter-episode gaps")
  func detectsLongGapsAsEvergreen() {
    // Recent episode but ~90d+ between drops — the user shouldn't have to
    // care about freshness for a show like this.
    let quarterly = dates(daysAgo: [0, 95, 190, 285])
    #expect(FreshnessCadence.infer(from: quarterly, now: now) == .evergreen)
  }

  @Test("caps inference to the most recent samples for shows with long histories")
  func capsToMostRecentSamples() {
    // Recent block: `inferenceMaxSamples` 7-day-spaced episodes (newest 0d,
    // oldest just under 700d back). Ancient block: another full sample
    // window of monthly-spaced episodes from 800d back. Without the cap, the
    // ancient block dominates the median and inference flips to .monthly;
    // with the cap, only the recent block contributes → .twiceWeekly.
    let recent = stride(
      from: 0.0,
      to: Double(FreshnessCadence.inferenceMaxSamples) * 7,
      by: 7
    )
    .map { $0 }
    let ancient = stride(
      from: 800.0,
      to: 800.0 + Double(FreshnessCadence.inferenceMaxSamples) * 30,
      by: 30
    )
    .map { $0 }
    #expect(
      FreshnessCadence.infer(from: dates(daysAgo: recent + ancient), now: now) == .twiceWeekly
    )
  }
}
