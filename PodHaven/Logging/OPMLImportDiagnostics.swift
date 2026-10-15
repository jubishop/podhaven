// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import Sentry

extension Container {
  var opmlDiagnosticCapture: Factory<@Sendable (Sentry.Event, [Sentry.Attachment]) -> Void> {
    Factory(self) {
      { event, attachments in
        SentrySDK.capture(event: event) { scope in
          for attachment in attachments {
            scope.addAttachment(attachment)
          }
        }
      }
    }
  }

  var opmlImportDiagnostics: Factory<OPMLImportDiagnostics> {
    Factory(self) { OPMLImportDiagnostics() }.scope(.cached)
  }
}

struct OPMLImportDiagnostics: Sendable {
  static let maximumAttachmentBytes = 1024 * 1024
  static let minimumCaptureInterval: Duration = .seconds(15 * 60)

  @DynamicInjected(\.opmlDiagnosticCapture) private var capture
  @DynamicInjected(\.continuousClockNow) private var continuousClockNow

  private static let log = Log.as(LogSubsystem.Feed.opml)

  private let lastCapture = ThreadSafe<ContinuousClock.Instant?>(nil)

  fileprivate init() {}

  func parseFailed(_ error: any Error, data: Data, fileName: String) {
    let now = continuousClockNow()
    let allowed = lastCapture { last in
      if let last, now - last < Self.minimumCaptureInterval { return false }
      last = now
      return true
    }
    guard allowed else {
      Self.log.debug("parseFailed: skipped diagnostic upload within capture interval")
      return
    }

    let attachedData = Data(data.prefix(Self.maximumAttachmentBytes))
    let event = Sentry.Event(level: .error)
    event.message = SentryMessage(formatted: "OPML import parse failure")
    event.fingerprint = ["opml-import-parse-failure"]
    event.context = [
      "opml_import": [
        "fileName": fileName,
        "bytes": data.count,
        "attachedBytes": attachedData.count,
        "truncated": attachedData.count < data.count,
        "error": String(describing: ErrorKit.loggableMessage(for: error)),
      ]
    ]
    capture(
      event,
      [Sentry.Attachment(data: attachedData, filename: "import.opml", contentType: "text/x-opml")]
    )
    Self.log.debug(
      "parseFailed: captured diagnostic with \(attachedData.count) of \(data.count) bytes"
    )
  }
}
