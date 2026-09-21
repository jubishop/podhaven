// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Logging
import Testing

@testable import PodHaven

@Suite("Sentry structured log transport", .container)
struct SentryLogHandlerTests {
  @Test("MetricKit exit summaries forward only public aggregate fields")
  func forwardsOnlyPublicExitSummaryFields() throws {
    let logger = try #require(Container.shared.sentryLogger() as? FakeSentryLogger)
    let handler = SentryLogHandler(label: "PodHaven/MetricKit")
    handler.log(
      event: LogEvent(
        level: .critical,
        message: "MetricKit foreground-exit metrics — abnormal: appWatchdog",
        metadata: [
          "metricKit.kind": "aggregate_exits", "metricKit.scope": "foreground",
          "metricKit.periodStart": "2026-09-19T12:00:00Z",
          "metricKit.periodEnd": "2026-09-20T12:00:00Z",
          "metricKit.latestVersion": "1.2.1", "metricKit.payloadBuild": "573",
          "metricKit.multipleVersions": "true", "metricKit.attribution": "reporting_period",
          "appWatchdog": "2", "memoryResourceLimit": "1",
          "metricKitDiagnostic": "private diagnostic", "url": "private media URL",
        ],
        source: "test",
        file: #fileID,
        function: #function,
        line: #line
      )
    )
    let record = try #require(logger.records.first)
    #expect(record.severity == "fatal")
    #expect(record.attributes["metricKit.kind"] as? String == "aggregate_exits")
    #expect(record.attributes["metricKit.scope"] as? String == "foreground")
    #expect(record.attributes["metricKit.periodStart"] as? String == "2026-09-19T12:00:00Z")
    #expect(record.attributes["metricKit.periodEnd"] as? String == "2026-09-20T12:00:00Z")
    #expect(record.attributes["metricKit.latestVersion"] as? String == "1.2.1")
    #expect(record.attributes["metricKit.payloadBuild"] as? String == "573")
    #expect(record.attributes["metricKit.multipleVersions"] as? String == "true")
    #expect(record.attributes["metricKit.attribution"] as? String == "reporting_period")
    #expect(record.attributes["metricKit.appWatchdog"] as? String == "2")
    #expect(record.attributes["metricKit.memoryResourceLimit"] as? String == "1")
    #expect(record.attributes["metricKitDiagnostic"] == nil)
    #expect(record.attributes["url"] == nil)
    #expect(record.attributes["buildNumber"] as? String == AppInfo.buildNumber)
  }
}
