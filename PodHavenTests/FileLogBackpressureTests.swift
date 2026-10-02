// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Logging
import Testing

@testable import PodHaven

@Suite("File logging backpressure", .container)
struct FileLogBackpressureTests {
  @Test("throttled records skip metadata construction")
  func throttledRecordsSkipMetadata() throws {
    Container.shared.fakeContinuousClock().freeze()
    let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let builds = ThreadSafe(0)
    var handler = FileLogHandler(
      label: "PodHaven/LazyTest",
      fileURL: url,
      maxFileSizeBytes: 100_000,
      targetFileSizeBytes: 75_000,
      writeSynchronously: { _ in true }
    )
    handler.metadataProvider = .init {
      builds { $0 += 1 }
      return ["context": "expensive metadata"]
    }
    for _ in 0..<500 {
      handler.log(
        event: LogEvent(
          level: .debug,
          message: "routine record",
          metadata: nil,
          source: "PodHavenTests",
          file: #fileID,
          function: #function,
          line: #line
        )
      )
    }
    FileLogHandler.flush(fileURL: url)
    #expect(builds() == 50)
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(text.contains("dropped 450 entries"))
  }

  @Test("background routine app logs format on the writer instead of the main thread")
  @MainActor func backgroundRoutineFormattingUsesWorker() throws {
    Container.shared.sharedState().$scenePhase.new(.background)
    let formattedOnMain = ThreadSafe<[Bool]>([])
    let files = [AppInfo.logFileURL, AppInfo.recentLogFileURL]
    for file in files {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
    }
    for var handler in AppLauncher.fileLogHandlers(label: "PodHaven/BackgroundTest") {
      handler.metadataProvider = .init {
        formattedOnMain { $0.append(Thread.isMainThread) }
        return [:]
      }
      handler.log(
        event: LogEvent(
          level: .debug,
          message: "routine background work",
          metadata: nil,
          source: "PodHavenTests",
          file: #fileID,
          function: #function,
          line: #line
        )
      )
    }
    FileLogHandler.flush()
    #expect(formattedOnMain().count == 2)
    #expect(formattedOnMain().allSatisfy { !$0 })
  }

  @Test("failed appends refund admission and preserve pending suppression counts")
  func failedAppendsPreserveAdmission() throws {
    let clock = Container.shared.fakeContinuousClock()
    clock.freeze()
    let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let url = directory.appendingPathComponent("log.ndjson")
    defer { try? FileManager.default.removeItem(at: directory) }
    let handler = FileLogHandler(
      label: "PodHaven/FailureTest",
      fileURL: url,
      maxFileSizeBytes: 100_000,
      targetFileSizeBytes: 75_000,
      writeSynchronously: { _ in true }
    )
    let event = LogEvent(
      level: .debug,
      message: "routine",
      metadata: nil,
      source: "PodHavenTests",
      file: #fileID,
      function: #function,
      line: #line
    )
    handler.log(event: event)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for _ in 0..<50 { handler.log(event: event) }
    FileLogHandler.flush(fileURL: url)
    #expect(try String(contentsOf: url, encoding: .utf8).split(separator: "\n").count == 50)
    for _ in 0..<10 { handler.log(event: event) }
    try FileManager.default.removeItem(at: directory)
    clock.advance(by: .seconds(1))
    handler.log(event: event)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    handler.log(event: event)
    FileLogHandler.flush(fileURL: url)
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(text.split(separator: "\n").count == 2)
    #expect(text.contains("dropped 10 entries"))
  }

  @Test("concurrent producers account for every accepted and suppressed record")
  func concurrentProducersPreserveAccounting() async throws {
    Container.shared.fakeContinuousClock().freeze()
    let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let handler = FileLogHandler(
      label: "PodHaven/ConcurrentTest",
      fileURL: url,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 8_000_000,
      writeSynchronously: { _ in false }
    )
    await withTaskGroup(of: Void.self) { group in
      for site in 1...8 {
        group.addTask {
          for _ in 0..<500 {
            handler.log(
              event: LogEvent(
                level: .debug,
                message: "routine",
                metadata: nil,
                source: "PodHavenTests",
                file: "Concurrent.swift",
                function: "producer()",
                line: UInt(site)
              )
            )
          }
        }
      }
    }
    FileLogHandler.flush(fileURL: url)
    let records = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
      .map {
        try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
      }
    for site in 1...8 {
      let messages = records.filter { ($0["line"] as? Int) == site }
        .compactMap { $0["message"] as? String }
      let accounted = messages.reduce(0) { count, message in
        if message == "routine" { return count + 1 }
        let words = message.split(separator: " ")
        guard let dropped = words.firstIndex(of: "dropped"), dropped + 1 < words.count else {
          return count
        }
        return count + (Int(words[dropped + 1]) ?? 0)
      }
      #expect(accounted == 500)
    }
  }

  @Test("an occupied writer bounds routine records across competing call sites")
  func occupiedWriterBoundsRoutineRecords() throws {
    Container.shared.fakeContinuousClock().freeze()
    let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let handler = FileLogHandler(
      label: "PodHaven/BackpressureTest",
      fileURL: url,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 8_000_000,
      writeSynchronously: { $0 == .critical }
    )
    var trigger = handler
    trigger.metadataProvider = .init {
      for site in 1...20 {
        for _ in 0..<100 {
          handler.log(
            event: LogEvent(
              level: .debug,
              message: "routine",
              metadata: nil,
              source: "PodHavenTests",
              file: "Backpressure.swift",
              function: "burst()",
              line: UInt(site)
            )
          )
        }
      }
      return [:]
    }
    trigger.log(
      event: LogEvent(
        level: .critical,
        message: "critical",
        metadata: nil,
        source: "PodHavenTests",
        file: "Backpressure.swift",
        function: "trigger()",
        line: 21
      )
    )
    FileLogHandler.flush(fileURL: url)
    let records = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
      .map {
        try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
      }
    let messages = records.compactMap { $0["message"] as? String }
    let retained = messages.filter { $0 == "routine" }.count
    #expect(retained > 0)
    #expect(retained <= 256)
    #expect(messages.filter { $0 == "critical" }.count == 1)
    let suppressed = messages.reduce(0) { count, message in
      let words = message.split(separator: " ")
      guard let dropped = words.firstIndex(of: "dropped"), dropped + 1 < words.count else {
        return count
      }
      return count + (Int(words[dropped + 1]) ?? 0)
    }
    #expect(retained + suppressed == 2_000)
    let lastRoutine = try #require(messages.lastIndex(of: "routine"))
    let firstSummary = try #require(messages.firstIndex { $0.contains("dropped") })
    #expect(lastRoutine < firstSummary)
  }
}
