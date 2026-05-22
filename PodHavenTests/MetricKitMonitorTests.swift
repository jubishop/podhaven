// Copyright Justin Bishop, 2026

import Foundation
import Logging
import Testing

@testable import PodHaven

@Suite("of MetricKitMonitor tests")
struct MetricKitMonitorTests {
  @Test("an all-normal background-exit payload logs at .info")
  func normalExitsLogAtInfo() {
    let directive = MetricKitMonitor.exitMetricDirective(
      for: BackgroundExitCounts(normalAppExit: 7)
    )
    #expect(directive.level == .info)
  }

  @Test("a background CPU resource-limit kill escalates to .critical")
  func cpuKillEscalatesToCritical() {
    let directive = MetricKitMonitor.exitMetricDirective(
      for: BackgroundExitCounts(normalAppExit: 3, cpuResourceLimit: 1)
    )
    #expect(directive.level == .critical)
    #expect(directive.message.contains("cpuResourceLimit: 1"))
  }

  @Test("a background memory-pressure exit is routine iOS reclaim and logs at .info")
  func memoryPressureExitLogsAtInfo() {
    let directive = MetricKitMonitor.exitMetricDirective(
      for: BackgroundExitCounts(memoryPressure: 2)
    )
    #expect(directive.level == .info)
  }

  @Test("a background memory resource-limit kill escalates to .critical")
  func memoryResourceLimitKillEscalatesToCritical() {
    let directive = MetricKitMonitor.exitMetricDirective(
      for: BackgroundExitCounts(memoryResourceLimit: 1)
    )
    #expect(directive.level == .critical)
  }

  @Test("a diagnostic directive carries the payload JSON verbatim in metadata")
  func diagnosticDirectiveCarriesJSON() throws {
    let json =
      #"{"callStackTree":{"callStacks":[]},"diagnosticMetaData":{"platformArchitecture":"arm64e"}}"#
    let directive = MetricKitMonitor.diagnosticDirective(
      category: .cpuException,
      json: Data(json.utf8)
    )

    #expect(directive.level == .notice)
    #expect(directive.message == "MetricKit cpuException diagnostic received")

    let stored = try #require(directive.metadata["metricKitDiagnostic"])
    #expect(stored == .string(json))
  }
}
