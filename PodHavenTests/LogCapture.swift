// Copyright Justin Bishop, 2026

import Foundation
import Logging

@testable import PodHaven

// Process-wide swift-log capture. `LoggingSystem.bootstrap` is one-shot per
// process and the test target runs cases concurrently, so this is the only
// way to observe `Self.log.warning(...)` output without races.
//
// Buffer is intentionally append-only for the life of the process: a clear
// method would race with sibling tests under concurrent execution and has
// no safe semantics. Tests filter their own messages by embedding a unique
// discriminator (e.g. a per-test `line` value) in the log site they're
// stress-testing.
enum LogCapture {
  struct Captured: Sendable {
    let label: String
    let level: Logging.Logger.Level
    let message: String
  }

  private static let installed = ThreadSafe(false)
  private static let buffer = ThreadSafe<[Captured]>([])

  // Bootstraps a multiplex of (existing default) + a capturing handler.
  // Idempotent. Must be called from at least one test that wants capture
  // before any log emission it cares about; subsequent calls are no-ops.
  static func installOnce() {
    let alreadyInstalled = installed { wasInstalled in
      let was = wasInstalled
      wasInstalled = true
      return was
    }
    guard !alreadyInstalled else { return }
    LoggingSystem.bootstrap { label in
      MultiplexLogHandler([
        StreamLogHandler.standardError(label: label),
        CapturingLogHandler(label: label),
      ])
    }
  }

  static func captured() -> [Captured] {
    buffer()
  }

  static func append(_ entry: Captured) {
    buffer { $0.append(entry) }
  }
}

private struct CapturingLogHandler: LogHandler {
  var metadata: Logging.Logger.Metadata = [:]
  var metadataProvider: Logging.Logger.MetadataProvider?
  var logLevel: Logging.Logger.Level = .trace

  let label: String

  subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
    get { metadata[metadataKey] }
    set { metadata[metadataKey] = newValue }
  }

  func log(event: LogEvent) {
    LogCapture.append(
      LogCapture.Captured(
        label: label,
        level: event.level,
        message: event.message.description
      )
    )
  }
}
