// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import Sentry

extension Container {
  var siriDiagnosticCapture: Factory<@Sendable (Sentry.Event) -> Void> {
    Factory(self) { { event in SentrySDK.capture(event: event) } }
  }

  var siriResolutionDiagnostics: Factory<SiriResolutionDiagnostics> {
    Factory(self) { SiriResolutionDiagnostics() }.scope(.cached)
  }
}

struct SiriResolutionDiagnostics: Sendable {
  @DynamicInjected(\.siriDiagnosticCapture) private var capture
  private let journal: SiriResolutionJournal
  private let extensionJournal: SiriResolutionJournal
  private let lastCapture = ThreadSafe<[String: Date]>([:])
  private static let log = Log.as("SiriResolutionDiagnostics")

  fileprivate init() {
    let directory = Container.shared.siriCatalogFile().url.deletingLastPathComponent()
    journal = SiriResolutionJournal(
      url: directory.appendingPathComponent("siri-app-resolutions.json"),
      sessionID: FileLogHandler.sessionID,
      version: AppInfo.version,
      build: AppInfo.buildNumber,
      commit: AppInfo.gitCommitHash,
      process: "app"
    )
    extensionJournal = SiriResolutionJournal(
      url: directory.appendingPathComponent("siri-extension-resolutions.json"),
      sessionID: FileLogHandler.sessionID,
      version: AppInfo.version,
      build: AppInfo.buildNumber,
      commit: AppInfo.gitCommitHash,
      process: "extension"
    )
  }

  func record(_ summary: SiriResolutionOperation.Summary) {
    journal.record(summary)
    _ = captureIfNeeded(summary, deferred: false)
  }

  @concurrent func captureExtensionFailures() async {
    let defaults = Container.shared.standardDefaults()
    let key = "siriReportedExtensionOperations"
    var reported = [String].load(from: defaults, forKey: key) ?? []
    for record in extensionJournal.read() {
      let id = record.summary.operationID.uuidString
      guard !reported.contains(id) else { continue }
      if captureIfNeeded(record.summary, deferred: true, origin: record) {
        reported.append(id)
        reported = Array(reported.suffix(16))
        reported.store(to: defaults, forKey: key)
      }
    }
  }

  func attachments() -> [Sentry.Attachment] {
    [("siri-app-resolutions.json", journal), ("siri-extension-resolutions.json", extensionJournal)]
      .compactMap { name, journal in
        let records = journal.read()
        guard !records.isEmpty else { return nil }
        let data: Data
        do { data = try JSONEncoder().encode(records) } catch {
          Self.log.caughtError("Could not encode retained Siri summaries", error)
          return nil
        }
        guard data.count <= SiriResolutionJournal.maximumBytes else { return nil }
        return Sentry.Attachment(data: data, filename: name, contentType: "application/json")
      }
  }

  private func captureIfNeeded(
    _ summary: SiriResolutionOperation.Summary,
    deferred: Bool,
    origin: SiriResolutionJournal.Record? = nil
  ) -> Bool {
    guard summary.phase == .finished else { return false }
    let slow = summary.totalMs >= 1_000
    let failed = !["unique", "ambiguous"].contains(summary.outcome)
    guard slow || failed else { return false }
    let key = deferred ? "extension" : (slow ? "slow" : "failed")
    let now = Date()
    let allowed = lastCapture { captures in
      if let last = captures[key], now.timeIntervalSince(last) < 60 { return false }
      captures[key] = now
      return true
    }
    guard allowed else { return false }
    let event = Sentry.Event(level: .warning)
    event.message = SentryMessage(formatted: "Siri catalog resolution diagnostic")
    event.fingerprint = ["siri-catalog-resolution", key]
    event.tags = [
      "siri-operation-id": summary.operationID.uuidString,
      "siri-outcome": summary.outcome,
      "siri-diagnostic": key,
      "log-session-id": FileLogHandler.sessionID,
      "git-commit-hash": AppInfo.gitCommitHash,
    ]
    event.context = [
      "siri_resolution": [
        "operationID": summary.operationID.uuidString,
        "deferredFromExtension": deferred,
        "observation": deferred ? "deferred_extension_upload" : "operation_completion",
        "operationSessionID": origin?.sessionID ?? FileLogHandler.sessionID,
        "operationBuild": origin?.build ?? AppInfo.buildNumber,
        "operationCommit": origin?.commit ?? AppInfo.gitCommitHash,
        "readMs": summary.readMs, "decodeMs": summary.decodeMs, "matchMs": summary.matchMs,
        "totalMs": summary.totalMs, "bytes": summary.bytes, "entries": summary.entries,
        "maxTitleBytes": summary.maxTitleBytes, "mode": summary.mode,
        "requestMode": summary.requestMode, "mediaType": summary.mediaType,
        "callbackMainThread": summary.callbackMainThread,
        "workerMainThread": summary.workerMainThread, "outcome": summary.outcome,
      ]
    ]
    capture(event)
    return true
  }
}
