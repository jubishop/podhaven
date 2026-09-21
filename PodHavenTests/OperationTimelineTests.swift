// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import Testing

@testable import PodHaven

@Suite("Operation timeline", .container)
struct OperationTimelineTests {
  private struct Unencodable: DefaultsStorable, Codable {
    enum Failure: Error { case expected }
    func encode(to encoder: any Encoder) throws { throw Failure.expected }
  }

  private struct InspectingStore: KeyValueStore {
    let inspect: @Sendable () -> Void
    var allKeys: [String] { [] }
    func data(forKey defaultName: String) -> Data? { nil }
    func string(forKey defaultName: String) -> String? { nil }
    func set(_ value: Any?, forKey defaultName: String) { inspect() }
    func removeObject(forKey defaultName: String) { inspect() }
  }

  @Test("persistence exposes pending writes without recording private keys or values")
  func pendingWrite() throws {
    try LogCapture.withSink { sink in
      let store = InspectingStore {
        let records = sink.captured().filter { $0.metadata["operationKind"] == "defaults.store" }
        #expect(records.map { $0.metadata["operationState"] } == ["started", "encoded"])
        #expect(records.last?.metadata["byteCount"] == "17")
      }
      "private-payload".store(to: store, forKey: "private-key")
      let records = sink.captured().filter { $0.metadata["operationKind"] == "defaults.store" }
      #expect(records.map { $0.metadata["operationState"] } == ["started", "encoded", "completed"])
      #expect(Set(records.compactMap { $0.metadata["operationID"] }).count == 1)
      let times = try records.map { try #require(Double($0.metadata["uptime"] ?? "")) }
      #expect(times == times.sorted())
      #expect(records.allSatisfy { !String(describing: $0).contains("private-") })
    }
  }

  @Test("detail phases expose pending and completed work even below the warning threshold")
  func pendingDetail() throws {
    try LogCapture.withSink { sink in
      Container.shared.podcastDetailPerformanceDiagnostics()
        .measure(.filterRefresh, episodeCount: 12) {
          let records = sink.captured()
            .filter { $0.metadata["operationKind"] == "detail.filterRefresh" }
          #expect(records.count == 1)
          #expect(records.first?.metadata["operationState"] == "started")
          #expect(records.first?.metadata["count"] == "12")
        }
      let records = sink.captured()
        .filter { $0.metadata["operationKind"] == "detail.filterRefresh" }
      #expect(records.map { $0.metadata["operationState"] } == ["started", "completed"])
      let first = try #require(records.first)
      #expect(records.last?.metadata["operationID"] == first.metadata["operationID"])
    }
  }

  @Test("failed encoding ends the operation without writing")
  func failedEncoding() {
    LogCapture.withSink { sink in
      Unencodable()
        .store(
          to: InspectingStore { Issue.record("Encoding failure must not write") },
          forKey: "fixture"
        )
      let records = sink.captured().filter { $0.metadata["operationKind"] == "defaults.store" }
      #expect(records.map { $0.metadata["operationState"] } == ["started", "failed"])
    }
  }

  @Test("optional removal exposes pending and completed work")
  func pendingRemoval() {
    LogCapture.withSink { sink in
      let value: String? = nil
      value.store(
        to: InspectingStore {
          let records = sink.captured().filter { $0.metadata["operationKind"] == "defaults.remove" }
          #expect(records.map { $0.metadata["operationState"] } == ["started"])
        },
        forKey: "fixture"
      )
      let records = sink.captured().filter { $0.metadata["operationKind"] == "defaults.remove" }
      #expect(records.map { $0.metadata["operationState"] } == ["started", "completed"])
    }
  }

  @Test("busy detail activity does not suppress other operation sites in the file log")
  func independentOperationRateLimits() throws {
    let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ndjson")
    defer { try? FileManager.default.removeItem(at: file) }
    let handler = FileLogHandler(
      label: "PodHaven/OperationTimelineTests",
      fileURL: file,
      maxFileSizeBytes: AppInfo.recentLogMaxFileSizeBytes,
      targetFileSizeBytes: AppInfo.recentLogTargetFileSizeBytes,
      historyPolicy: .preservePreviousSession,
      writeSynchronously: { _ in true }
    )
    let captured = LogCapture.withSink { sink in
      let diagnostics = Container.shared.podcastDetailPerformanceDiagnostics()
      for _ in 0..<100 {
        diagnostics.measure(.filterRefresh, episodeCount: 12) {}
      }
      diagnostics.measure(.episodeProjection, episodeCount: 12) {}
      true.store(to: InspectingStore {}, forKey: "fixture")
      return sink.captured()
    }
    for entry in captured {
      handler.log(
        event: LogEvent(
          level: entry.level,
          message: "\(entry.message)",
          metadata: entry.metadata.mapValues { .string($0) },
          source: entry.source,
          file: entry.file,
          function: entry.function,
          line: entry.line
        )
      )
    }
    FileLogHandler.flush(fileURL: file)
    let entries = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
      .map {
        try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
      }
    let metadata = entries.compactMap { $0["metadata"] as? [String: String] }
    #expect(entries.contains { ($0["message"] as? String)?.contains("rate limit") == true })
    #expect(
      metadata.filter { $0["operationKind"] == "detail.episodeProjection" }
        .compactMap { $0["operationState"] } == ["started", "completed"]
    )
    #expect(
      metadata.filter { $0["operationKind"] == "defaults.store" }
        .compactMap { $0["operationState"] } == ["started", "encoded", "completed"]
    )
  }
}
