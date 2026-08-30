// Copyright Justin Bishop, 2026

import FactoryKit
import Sentry
import Testing

@testable import PodHaven

@Suite("Sentry event processor", .container)
struct SentryEventProcessorTests {
  @Test("only recovered same-process App Hangs receive performance context")
  func onlyRecoveredAppHangsReceivePerformanceContext() throws {
    Container.shared.podcastDetailPerformanceDiagnostics()
      .measure(
        .episodeProjection,
        episodeCount: 10
      ) {}
    let processor = Container.shared.sentryEventProcessor()

    let recovered = try #require(
      processor.process(Self.event(type: "App Hang Fully Blocked", mechanism: "AppHang"))
    )
    #expect(recovered.context?["podcast_detail_performance"] != nil)

    let fatal = try #require(
      processor.process(
        Self.event(type: "Fatal App Hang Fully Blocked", mechanism: "AppHang")
      )
    )
    #expect(fatal.context?["podcast_detail_performance"] == nil)

    let metricKit = try #require(
      processor.process(Self.event(type: "MXHangDiagnostic", mechanism: "mx_hang_diagnostic"))
    )
    #expect(metricKit.context?["podcast_detail_performance"] == nil)
  }

  @Test("MetricKit disk-write diagnostics remain filtered")
  func diskWriteDiagnosticsRemainFiltered() {
    let event = Self.event(
      type: "MXDiskWriteException",
      mechanism: "mx_disk_write_exception"
    )
    #expect(Container.shared.sentryEventProcessor().process(event) == nil)
  }

  private static func event(type: String, mechanism: String) -> Sentry.Event {
    let event = Sentry.Event(level: .error)
    let exception = Exception(value: type, type: type)
    exception.mechanism = Mechanism(type: mechanism)
    event.exceptions = [exception]
    return event
  }
}
