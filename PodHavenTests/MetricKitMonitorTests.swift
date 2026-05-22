// Copyright Justin Bishop, 2026

import Foundation
import Logging
import Testing

@testable import PodHaven

@Suite("of MetricKitMonitor tests")
struct MetricKitMonitorTests {
  @Test(
    "each abnormal background-exit reason escalates to .critical",
    arguments: [
      BackgroundExitCounts(memoryResourceLimit: 1),
      BackgroundExitCounts(cpuResourceLimit: 1),
      BackgroundExitCounts(badAccess: 1),
      BackgroundExitCounts(abnormal: 1),
      BackgroundExitCounts(illegalInstruction: 1),
      BackgroundExitCounts(appWatchdog: 1),
      BackgroundExitCounts(suspendedWithLockedFile: 1),
      BackgroundExitCounts(backgroundTaskAssertionTimeout: 1),
    ]
  )
  func abnormalExitsEscalateToCritical(counts: BackgroundExitCounts) {
    #expect(MetricKitMonitor.exitMetricDirective(for: counts).level == .critical)
  }

  @Test(
    "routine background-exit reasons stay at .info",
    arguments: [
      BackgroundExitCounts(normalAppExit: 7),
      BackgroundExitCounts(memoryPressure: 2),
      BackgroundExitCounts(),
    ]
  )
  func routineExitsLogAtInfo(counts: BackgroundExitCounts) {
    #expect(MetricKitMonitor.exitMetricDirective(for: counts).level == .info)
  }

  @Test("the .critical message is identical across payloads so Sentry groups recurrences")
  func criticalMessageStableAcrossCounts() {
    let first = MetricKitMonitor.exitMetricDirective(
      for: BackgroundExitCounts(normalAppExit: 3, cpuResourceLimit: 1)
    )
    let second = MetricKitMonitor.exitMetricDirective(
      for: BackgroundExitCounts(normalAppExit: 11, cpuResourceLimit: 4)
    )
    #expect(first.level == .critical)
    #expect(second.level == .critical)
    #expect(first.message == second.message)
  }

  @Test("the .critical message names every nonzero abnormal reason and omits zero ones")
  func criticalMessageNamesNonzeroAbnormalReasons() {
    let directive = MetricKitMonitor.exitMetricDirective(
      for: BackgroundExitCounts(cpuResourceLimit: 1, appWatchdog: 2)
    )
    #expect(directive.message.contains("cpuResourceLimit"))
    #expect(directive.message.contains("appWatchdog"))
    #expect(directive.message.contains("memoryResourceLimit") == false)
    #expect(directive.message.contains("badAccess") == false)
  }

  @Test("the exit directive carries per-reason counts in metadata for the NDJSON log")
  func exitDirectiveCarriesCountsInMetadata() {
    let directive = MetricKitMonitor.exitMetricDirective(
      for: BackgroundExitCounts(normalAppExit: 5, cpuResourceLimit: 1, appWatchdog: 2)
    )
    #expect(directive.metadata["normalAppExit"] == .string("5"))
    #expect(directive.metadata["cpuResourceLimit"] == .string("1"))
    #expect(directive.metadata["appWatchdog"] == .string("2"))
    #expect(directive.metadata["memoryResourceLimit"] == .string("0"))
  }

  @Test(
    "a diagnostic directive carries the payload JSON verbatim in metadata",
    arguments: [
      MetricKitDiagnosticCategory.crash,
      .hang,
      .cpuException,
      .diskWriteException,
      .appLaunch,
    ]
  )
  func diagnosticDirectiveCarriesJSON(category: MetricKitDiagnosticCategory) throws {
    let json =
      #"{"callStackTree":{"callStacks":[]},"diagnosticMetaData":{"platformArchitecture":"arm64e"}}"#
    let directive = MetricKitMonitor.diagnosticDirective(
      category: category,
      json: Data(json.utf8)
    )

    #expect(directive.level == .notice)
    #expect(directive.message == "MetricKit \(category.rawValue) diagnostic received")

    let stored = try #require(directive.metadata["metricKitDiagnostic"])
    #expect(stored == .string(json))
  }
}
