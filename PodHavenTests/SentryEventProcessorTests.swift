// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Sentry
import Testing

@testable import PodHaven

@Suite("Sentry event processor", .container)
struct SentryEventProcessorTests {
  @Test("events describe attachment file availability without including paths or contents")
  func attachmentAvailabilityIsIncluded() throws {
    let fileManager = Container.shared.fileManager()
    try fileManager.writeDataSynchronously(
      Data("private log contents".utf8),
      to: AppInfo.recentLogFileURL
    )
    let processed = try #require(
      Container.shared.sentryEventProcessor().process(Sentry.Event(level: .error))
    )
    let context = try #require(processed.context?["recent_log_files"] as? [String: Any])
    let app = try #require(context["app"] as? [String: Any])
    let widget = try #require(context["widget"] as? [String: Any])
    #expect(app["status"] as? String == "present")
    #expect(app["bytes"] as? Int64 == 20)
    #expect(app["limitBytes"] as? Int == AppInfo.recentLogMaxFileSizeBytes)
    #expect(widget["status"] as? String == "missing")
    #expect(context["observation"] as? String == "capture_time")
    #expect(context["observationSessionID"] as? String == FileLogHandler.sessionID)
    let json = String(decoding: try JSONSerialization.data(withJSONObject: context), as: UTF8.self)
    #expect(!json.contains("private log contents"))
    #expect(!json.contains(AppInfo.recentLogFileURL.path))
    #expect(!json.contains(WidgetInfo.recentLogFileURL.path))
  }

  @Test("an unavailable tail reports its state without dropping the event")
  func unavailableTailDoesNotDropEvent() throws {
    let fileManager = try #require(Container.shared.fileManager() as? FakeFileManager)
    try fileManager.writeDataSynchronously(Data("log".utf8), to: AppInfo.recentLogFileURL)
    fileManager.setFileSizeError(CocoaError(.fileReadNoPermission), for: AppInfo.recentLogFileURL)
    let processed = try #require(
      Container.shared.sentryEventProcessor().process(Sentry.Event(level: .fatal))
    )
    let context = try #require(processed.context?["recent_log_files"] as? [String: Any])
    let app = try #require(context["app"] as? [String: Any])
    #expect(app["status"] as? String == "unavailable")
    #expect(app["bytes"] == nil)
  }

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
