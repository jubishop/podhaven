// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Logging
import Sentry
import Testing

@testable import PodHaven

@Suite("of MetricKitMonitor tests", .container)
struct MetricKitMonitorTests {
  private struct Payload: MetricKitMetricReporting {
    var foregroundExitCounts: ForegroundExitCounts?
    var backgroundExitCounts: BackgroundExitCounts?
    let reportingPeriod = MetricKitReportingPeriod(
      begin: Date(timeIntervalSince1970: 1_700_000_000),
      end: Date(timeIntervalSince1970: 1_700_086_400),
      latestApplicationVersion: "1.2.1",
      applicationBuildVersion: "573",
      includesMultipleApplicationVersions: true
    )
  }

  private struct ExitEvent {
    let level: SentryLevel
    let message: String?
    let fingerprint: [String]?
    let tags: [String: String]?
    let context: [String: String]?
  }

  private func sentryEvents(_ payloads: [Payload]) -> [ExitEvent] {
    let captured = ThreadSafe<[ExitEvent]>([])
    Container.shared.metricKitExitCapture.context(.test) {
      { event in
        let exitEvent = ExitEvent(
          level: event.level,
          message: event.message?.formatted,
          fingerprint: event.fingerprint,
          tags: event.tags,
          context: event.context?["metrickit_exit"] as? [String: String]
        )
        captured { $0.append(exitEvent) }
      }
    }
    let monitor = MetricKitMonitor()
    for payload in payloads {
      monitor.receive(payload)
    }
    return captured()
  }

  @Test("foreground watchdog and memory-limit counts reach the diagnostic logger")
  func foregroundExitsReachDiagnosticLogger() {
    LogCapture.withSink { sink in
      MetricKitMonitor()
        .receive(
          Payload(
            foregroundExitCounts: ForegroundExitCounts(memoryResourceLimit: 2, appWatchdog: 1),
            backgroundExitCounts: BackgroundExitCounts(normalAppExit: 4)
          )
        )
      let captured = sink.captured().filter { $0.label == "PodHaven/MetricKit" }
      #expect(captured.count == 2)
      #expect(
        captured.contains {
          $0.level == .error && $0.message.contains("foreground-exit")
            && $0.message.contains("memoryResourceLimit") && $0.message.contains("appWatchdog")
        }
      )
      #expect(captured.contains { $0.message.contains("background-exit") && $0.level == .info })
      for entry in captured {
        #expect(entry.metadata["metricKit.kind"] == "aggregate_exits")
        #expect(entry.metadata["metricKit.periodStart"] == "2023-11-14T22:13:20Z")
        #expect(entry.metadata["metricKit.periodEnd"] == "2023-11-15T22:13:20Z")
        #expect(entry.metadata["metricKit.latestVersion"] == "1.2.1")
        #expect(entry.metadata["metricKit.payloadBuild"] == "573")
        #expect(entry.metadata["metricKit.multipleVersions"] == "true")
        #expect(entry.metadata["metricKit.attribution"] == "reporting_period")
      }
      let foreground = captured.first { $0.metadata["metricKit.scope"] == "foreground" }
      #expect(foreground?.metadata["appWatchdog"] == "1")
      #expect(foreground?.metadata["memoryResourceLimit"] == "2")
    }
  }

  @Test(
    "each abnormal foreground reason is reported",
    arguments: [
      ForegroundExitCounts(memoryResourceLimit: 1), ForegroundExitCounts(badAccess: 1),
      ForegroundExitCounts(abnormal: 1), ForegroundExitCounts(illegalInstruction: 1),
      ForegroundExitCounts(appWatchdog: 1),
    ]
  )
  func foregroundReasonsAreReported(counts: ForegroundExitCounts) {
    LogCapture.withSink { sink in
      MetricKitMonitor().receive(Payload(foregroundExitCounts: counts))
      #expect(sink.captured().contains { $0.level == .error })
    }
  }

  @Test("routine foreground exits stay local and missing exit metrics emit nothing")
  func routineAndMissingForegroundMetrics() {
    LogCapture.withSink { sink in
      MetricKitMonitor()
        .receive(Payload(foregroundExitCounts: ForegroundExitCounts(normalAppExit: 3)))
      #expect(sink.captured().count == 1)
      #expect(sink.captured().first?.level == .info)
    }
    LogCapture.withSink { sink in
      MetricKitMonitor().receive(Payload())
      #expect(sink.captured().isEmpty)
    }
  }

  @Test("payload attribution remains bounded and does not invent a missing build")
  func payloadAttributionIsBounded() {
    let period = MetricKitReportingPeriod(
      begin: Date(timeIntervalSince1970: 0),
      end: Date(timeIntervalSince1970: 1),
      latestApplicationVersion: String(repeating: "v", count: 1000),
      applicationBuildVersion: nil,
      includesMultipleApplicationVersions: false
    )
    #expect(period.metadata["metricKit.payloadBuild"] == "unknown")
    #expect(period.metadata["metricKit.latestVersion"]?.description.count == 64)
    #expect(period.metadata["metricKit.multipleVersions"] == "false")
    #expect(period.metadata["metricKit.attribution"] == "reporting_period")
  }
  @Test(
    "each abnormal background-exit reason escalates to .error",
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
  func abnormalExitsEscalateToError(counts: BackgroundExitCounts) {
    #expect(MetricKitMonitor.exitMetricDirective(for: counts).level == .error)
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

  @Test("abnormal exit summaries reach Sentry grouped by scope and abnormal reasons")
  func abnormalExitSummariesGroupByScopeAndReasons() throws {
    let events = sentryEvents([
      Payload(backgroundExitCounts: BackgroundExitCounts(memoryPressure: 7, badAccess: 1)),
      Payload(backgroundExitCounts: BackgroundExitCounts(memoryPressure: 6, appWatchdog: 1)),
      Payload(backgroundExitCounts: BackgroundExitCounts(normalAppExit: 9, appWatchdog: 4)),
      Payload(foregroundExitCounts: ForegroundExitCounts(appWatchdog: 1)),
      Payload(foregroundExitCounts: ForegroundExitCounts(badAccess: 1, appWatchdog: 2)),
    ])

    #expect(
      events.map(\.fingerprint) == [
        ["metrickit-exit", "background", "badAccess"],
        ["metrickit-exit", "background", "appWatchdog"],
        ["metrickit-exit", "background", "appWatchdog"],
        ["metrickit-exit", "foreground", "appWatchdog"],
        ["metrickit-exit", "foreground", "badAccess", "appWatchdog"],
      ]
    )
    try #require(events.count == 5)
    #expect(events.allSatisfy { $0.level == .error })
    #expect(events[1].message == events[2].message)

    let badAccess = try #require(events.first)
    #expect(badAccess.message == "MetricKit background-exit metrics — abnormal: badAccess")
    #expect(badAccess.tags == ["metrickit-exit": "background"])
    let context = try #require(badAccess.context)
    #expect(context["badAccess"] == "1")
    #expect(context["memoryPressure"] == "7")
    #expect(context["appWatchdog"] == "0")
    #expect(context["metricKit.scope"] == "background")
    #expect(context["metricKit.kind"] == "aggregate_exits")
    #expect(context["metricKit.periodStart"] == "2023-11-14T22:13:20Z")
    #expect(context["metricKit.periodEnd"] == "2023-11-15T22:13:20Z")
    #expect(context["metricKit.payloadBuild"] == "573")
    #expect(context["metricKit.multipleVersions"] == "true")
    #expect(events[3].tags == ["metrickit-exit": "foreground"])
    #expect(events[3].context?["metricKit.scope"] == "foreground")
  }

  @Test("routine exit summaries send no Sentry event")
  func routineExitSummariesSendNoSentryEvent() {
    let events = sentryEvents([
      Payload(
        foregroundExitCounts: ForegroundExitCounts(normalAppExit: 3),
        backgroundExitCounts: BackgroundExitCounts(normalAppExit: 4, memoryPressure: 2)
      ),
      Payload(),
    ])
    #expect(events.isEmpty)
  }

  @Test("the abnormal message names every nonzero abnormal reason and omits zero ones")
  func abnormalMessageNamesNonzeroAbnormalReasons() {
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
