// Copyright Justin Bishop, 2026

import Foundation
import Logging

@testable import PodHaven

// Process-wide swift-log bootstrap with per-test capture sinks. `LoggingSystem.bootstrap`
// is one-shot per process; Swift Testing runs cases concurrently, so capture installs
// once and routes events into whichever test's `@TaskLocal` sink is active.
//
// No tests call `withSink` yet — that is fine for now; install-once is for upcoming
// swift-log assertions without re-bootstrapping per case.
enum LogCapture {
  struct Captured: Sendable {
    let label: String
    let level: Logging.Logger.Level
    let message: String
    let source: String
    let file: String
    let function: String
    let line: UInt
  }

  final class Sink: Sendable {
    private let storage = ThreadSafe<[Captured]>([])

    func append(_ captured: Captured) {
      storage { $0.append(captured) }
    }

    func captured() -> [Captured] {
      storage()
    }
  }

  @TaskLocal fileprivate static var current: Sink?

  private static let installed = ThreadSafe(false)

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

  static func withSink<T>(_ operation: (Sink) throws -> T) rethrows -> T {
    let sink = Sink()
    return try $current.withValue(sink) { try operation(sink) }
  }

  static func withSink<T>(_ operation: (Sink) async throws -> T) async rethrows -> T {
    let sink = Sink()
    return try await $current.withValue(sink) { try await operation(sink) }
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
    guard let sink = LogCapture.current else { return }
    sink.append(
      LogCapture.Captured(
        label: label,
        level: event.level,
        message: event.message.description,
        source: event.source,
        file: event.file,
        function: event.function,
        line: event.line
      )
    )
  }
}
