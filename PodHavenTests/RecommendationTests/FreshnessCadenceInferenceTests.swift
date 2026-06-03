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
    #expect(FreshnessCadence.infer(from: []) == .weekly)
    #expect(FreshnessCadence.infer(from: dates(daysAgo: [0, 7])) == .weekly)
  }

  @Test("infers .hourly for shows publishing roughly every hour")
  func detectsHourlyCadence() {
    let hourly = stride(from: 0.0, to: 2.0, by: 1.0 / 24.0).map { $0 }
    #expect(FreshnessCadence.infer(from: dates(daysAgo: hourly)) == .hourly)
  }

  @Test("infers .twiceDaily for shows publishing every ~12 hours")
  func detectsTwiceDailyCadence() {
    let twiceDaily = stride(from: 0.0, to: 7.0, by: 0.5).map { $0 }
    #expect(FreshnessCadence.infer(from: dates(daysAgo: twiceDaily)) == .twiceDaily)
  }

  @Test("infers .daily for shows publishing every 1-2 days")
  func detectsDailyCadence() {
    // Daily band is (16h, 36h]: a once-a-day cadence (24h) lands squarely here.
    let weekdayNews = dates(daysAgo: [0, 1, 2, 3, 6, 7, 8, 9, 10])
    #expect(FreshnessCadence.infer(from: weekdayNews) == .daily)

    let strictDaily = dates(daysAgo: stride(from: 0.0, to: 30, by: 1).map { $0 })
    #expect(FreshnessCadence.infer(from: strictDaily) == .daily)
  }

  @Test("infers .weekly for shows publishing every 6-10 days")
  func detectsWeeklyCadence() {
    // Weekly band is (126h, 252h] ≈ (5.25d, 10.5d]: a 7-day cadence lands here.
    let strictWeekly = dates(daysAgo: stride(from: 0.0, to: 90, by: 7).map { $0 })
    #expect(FreshnessCadence.infer(from: strictWeekly) == .weekly)

    let everyTenDays = dates(daysAgo: stride(from: 0.0, to: 90, by: 10).map { $0 })
    #expect(FreshnessCadence.infer(from: everyTenDays) == .weekly)
  }

  @Test("infers .twiceWeekly for shows publishing a couple times a week")
  func detectsTwiceWeeklyCadence() {
    // Monday/Thursday pattern: gaps alternate 3 and 4 days (median 4 days),
    // within the (36h, 126h] ≈ (1.5d, 5.25d] twiceWeekly band.
    let mondayThursday = dates(daysAgo: [0, 3, 7, 10, 14, 17, 21])
    #expect(FreshnessCadence.infer(from: mondayThursday) == .twiceWeekly)
  }

  @Test("infers .monthly for shows publishing every 2-6 weeks")
  func detectsMonthlyCadence() {
    let strictMonthly = dates(daysAgo: stride(from: 0.0, to: 360, by: 30).map { $0 })
    #expect(FreshnessCadence.infer(from: strictMonthly) == .monthly)
  }

  @Test("infers from median spacing regardless of how old the latest episode is")
  func ignoresEpisodeRecency() {
    // Weekly cadence historically, with no new episodes in over a year. Recency
    // is irrelevant: a dormant weekly show is still .weekly, not .evergreen.
    let dormant = dates(daysAgo: stride(from: 400.0, to: 500, by: 7).map { $0 })
    #expect(FreshnessCadence.infer(from: dormant) == .weekly)
  }

  @Test("infers .evergreen for shows with very long inter-episode gaps")
  func detectsLongGapsAsEvergreen() {
    // ~90d+ between drops — the user shouldn't have to care about freshness for
    // a show like this. This is driven by the median gap, not episode recency.
    let quarterly = dates(daysAgo: [0, 95, 190, 285])
    #expect(FreshnessCadence.infer(from: quarterly) == .evergreen)
  }

  @Test("caps inference to the most recent samples for shows with long histories")
  func capsToMostRecentSamples() {
    // Recent block: `inferenceMaxSamples` 7-day-spaced episodes (newest 0d,
    // oldest just under 700d back). Ancient block: another full sample
    // window of monthly-spaced episodes from 800d back. Without the cap, the
    // ancient block dominates the median and inference flips to .monthly;
    // with the cap, only the recent block contributes → .weekly.
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
    #expect(FreshnessCadence.infer(from: dates(daysAgo: recent + ancient)) == .weekly)
  }
}
