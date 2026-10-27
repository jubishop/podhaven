// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import Sentry

extension Container {
  var sentryEventProcessor: Factory<SentryEventProcessor> {
    Factory(self) { SentryEventProcessor() }.scope(.cached)
  }
}

struct SentryEventProcessor: Sendable {
  @DynamicInjected(\.podcastDetailPerformanceDiagnostics) private
    var podcastDetailPerformanceDiagnostics

  private static let log = Log.as("SentryEventProcessor")

  // Sentry keeps this MetricKit slug private, so the serialized mechanism
  // string is the only API available to event processors.
  private static let metricKitDiskWriteMechanism = "mx_disk_write_exception"

  fileprivate init() {}

  func process(_ event: Sentry.Event) -> Sentry.Event? {
    // Routine media downloads cross MetricKit's fixed cumulative disk-write
    // threshold. Keep the raw payload in MetricKitMonitor, but drop this noise
    // from Sentry while allowing other diagnostics through.
    let exceptions = event.exceptions ?? []
    let isDiskWriteDiagnostic = exceptions.contains {
      $0.mechanism?.type == Self.metricKitDiskWriteMechanism
    }
    guard !isDiskWriteDiagnostic else { return nil }

    var context = event.context ?? [:]
    context["recent_log_files"] = [
      "observation": "capture_time",
      "observationSessionID": FileLogHandler.sessionID,
      "app": fileContext(AppInfo.recentLogFileURL, limit: AppInfo.recentLogMaxFileSizeBytes),
      "widget": fileContext(
        WidgetInfo.recentLogFileURL,
        limit: WidgetInfo.recentLogMaxFileSizeBytes
      ),
    ]
    event.context = context

    // Recovered App Hangs are sent from the process that recorded these
    // samples. Fatal App Hangs and MetricKit hangs are persisted and sent later,
    // so current-process samples would be empty or unrelated to their incident.
    let isRecoveredAppHang = exceptions.contains { exception in
      guard exception.mechanism?.type.lowercased() == "apphang" else { return false }
      return exception.type?.localizedCaseInsensitiveContains("fatal app hang") != true
    }
    guard isRecoveredAppHang else { return event }
    context["podcast_detail_performance"] = podcastDetailPerformanceDiagnostics.sentryContext()
    event.context = context
    return event
  }

  private func fileContext(_ url: URL, limit: Int) -> [String: Any] {
    let fileManager = Container.shared.fileManager()
    guard fileManager.fileExists(atPath: url.path) else {
      return ["status": "missing", "limitBytes": limit]
    }
    let bytes: Int64
    do {
      bytes = try fileManager.fileSize(for: url)
    } catch {
      Self.log.caughtError("Unable to inspect recent-log file size", error, level: .notice)
      return ["status": "unavailable", "limitBytes": limit]
    }
    return [
      "status": "present", "bytes": bytes, "limitBytes": limit, "withinLimit": bytes <= limit,
    ]
  }
}
