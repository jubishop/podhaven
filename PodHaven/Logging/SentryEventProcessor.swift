// Copyright Justin Bishop, 2026

import FactoryKit
import Sentry

extension Container {
  var sentryEventProcessor: Factory<SentryEventProcessor> {
    Factory(self) { SentryEventProcessor() }.scope(.cached)
  }
}

struct SentryEventProcessor: Sendable {
  @DynamicInjected(\.podcastDetailPerformanceDiagnostics) private
    var podcastDetailPerformanceDiagnostics

  // Sentry keeps this MetricKit slug private, so the serialized mechanism
  // string is the only API available to event processors.
  private static let metricKitDiskWriteMechanism = "mx_disk_write_exception"

  fileprivate init() {}

  func process(_ event: Sentry.Event) -> Sentry.Event? {
    // Routine media downloads cross MetricKit's fixed cumulative disk-write
    // threshold. Keep the raw payload in MetricKitMonitor, but drop this noise
    // from Sentry while allowing other diagnostics through.
    guard let exceptions = event.exceptions else { return event }
    let isDiskWriteDiagnostic = exceptions.contains {
      $0.mechanism?.type == Self.metricKitDiskWriteMechanism
    }
    guard !isDiskWriteDiagnostic else { return nil }

    // Recovered App Hangs are sent from the process that recorded these
    // samples. Fatal App Hangs and MetricKit hangs are persisted and sent later,
    // so current-process samples would be empty or unrelated to their incident.
    let isRecoveredAppHang = exceptions.contains { exception in
      guard exception.mechanism?.type.lowercased() == "apphang" else { return false }
      return exception.type?.localizedCaseInsensitiveContains("fatal app hang") != true
    }
    guard isRecoveredAppHang else { return event }
    var context = event.context ?? [:]
    context["podcast_detail_performance"] = podcastDetailPerformanceDiagnostics.sentryContext()
    event.context = context
    return event
  }
}
