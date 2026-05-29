// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Logging
import Testing

@testable import PodHaven

@Suite("of FileLogHandler tests", .container)
struct FileLogHandlerTests {
  private struct DecodedEntry: Decodable {
    let message: String
    let line: UInt
    let timestamp: Int64
  }

  private func makeHandler(
    fileURL: URL,
    maxFileSizeBytes: Int,
    targetFileSizeBytes: Int,
    synchronous: Bool = true
  ) -> FileLogHandler {
    FileLogHandler(
      label: "PodHaven/FileLogTest",
      fileURL: fileURL,
      maxFileSizeBytes: maxFileSizeBytes,
      targetFileSizeBytes: targetFileSizeBytes,
      writeSynchronously: { _ in synchronous }
    )
  }

  private func tempFileURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("ndjson")
  }

  private func tearDownLogFile(_ fileURL: URL) {
    try? FileManager.default.removeItem(at: fileURL)
  }

  // A unique `line` per entry gives each its own rate-limit bucket, so the
  // writer drops nothing and the file stays deterministic.
  private func log(
    _ handler: FileLogHandler,
    message: String,
    file: String = "FileLogHandlerTests.swift",
    line: UInt
  ) {
    handler.log(
      event: LogEvent(
        level: .debug,
        message: "\(message)",
        metadata: nil,
        source: "PodHavenTests",
        file: file,
        function: "test()",
        line: line
      )
    )
  }

  // A partial line left behind by truncation fails to decode here.
  private func decodedEntries(at fileURL: URL) throws -> [DecodedEntry] {
    let decoder = JSONDecoder()
    return try String(decoding: try Data(contentsOf: fileURL), as: UTF8.self)
      .split(separator: "\n", omittingEmptySubsequences: true)
      .map { try decoder.decode(DecodedEntry.self, from: Data($0.utf8)) }
  }

  @Test("writes each entry as its own newline-delimited JSON line")
  func writesEntriesAsNewlineDelimitedJSON() throws {
    let fileURL = tempFileURL()
    defer { tearDownLogFile(fileURL) }

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000
    )

    for index in 0..<5 {
      log(handler, message: "entry-\(index)", line: UInt(index))
    }

    let entries = try decodedEntries(at: fileURL)
    #expect(entries.map(\.message) == (0..<5).map { "entry-\($0)" })
    #expect(entries.map(\.line) == (0..<5).map { UInt($0) })
  }

  @Test("truncation keeps whole JSON lines and keeps appending to the live file")
  func truncationKeepsWholeLinesAndKeepsAppending() throws {
    let fileURL = tempFileURL()
    defer { tearDownLogFile(fileURL) }

    // targetFileSizeBytes is well above the 64 KB read window, so each
    // truncation streams its surviving tail across several windows.
    let maxFileSizeBytes = 200_000
    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: maxFileSizeBytes,
      targetFileSizeBytes: 130_000
    )

    let written = 1_000
    let padding = String(repeating: "x", count: 120)
    for index in 0..<written {
      log(
        handler,
        message: "entry-\(String(format: "%04d", index))-\(padding)",
        line: UInt(index)
      )
    }

    let fileSize = try Data(contentsOf: fileURL).count
    #expect(fileSize <= maxFileSizeBytes)

    let entries = try decodedEntries(at: fileURL)
    #expect(!entries.isEmpty)
    #expect(entries.count < written)

    // Truncation drops a whole prefix, so survivors are a contiguous suffix
    // ending at the final write — a gap would mean a write missed the live file.
    let firstIndex = try #require(entries.first.map { Int($0.line) })
    #expect(entries.map { Int($0.line) } == Array(firstIndex..<written))
    #expect(entries.last?.message == "entry-\(String(format: "%04d", written - 1))-\(padding)")
  }

  @Test("truncation finds the cut boundary when an entry exceeds the read window")
  func truncationFindsBoundaryWhenEntryExceedsReadWindow() throws {
    let fileURL = tempFileURL()
    defer { tearDownLogFile(fileURL) }

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 150_000,
      targetFileSizeBytes: 100_000
    )

    // One entry far larger than the 64 KB read window: the truncation scan
    // must cross several windows to find its terminating newline. The giant
    // entry alone overflows the cap, so it is truncated away whole.
    log(handler, message: String(repeating: "z", count: 200_000), line: 0)

    for index in 1...40 {
      log(handler, message: "post-\(index)", line: UInt(index))
    }

    let entries = try decodedEntries(at: fileURL)
    #expect(entries.map(\.message) == (1...40).map { "post-\($0)" })
  }

  @Test("critical logs bypass rate limit at a throttled site")
  func criticalBypassesRateLimitAtThrottledSite() throws {
    let fileURL = tempFileURL()
    defer { tearDownLogFile(fileURL) }

    Container.shared.fakeContinuousClock().freeze()

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000
    )

    for _ in 0..<350 {
      log(handler, message: "storm", line: 1)
    }

    handler.log(
      event: LogEvent(
        level: .critical,
        message: "critical-after-storm",
        metadata: nil,
        source: "PodHavenTests",
        file: "FileLogHandlerTests.swift",
        function: "test()",
        line: 1
      )
    )

    let entries = try decodedEntries(at: fileURL)
    let suppressionMessage =
      "FileLogHandler rate limit — dropped 300 repeated entries from this log site"
    #expect(entries.count == 52)
    #expect(entries.filter { $0.message == "storm" }.count == 50)
    #expect(entries.contains { $0.message == suppressionMessage })
    #expect(entries.contains { $0.message == "critical-after-storm" })
  }

  @Test("rate limit drops repeated entries at one site after the burst is spent")
  func rateLimitDropsRepeatedEntries() throws {
    let fileURL = tempFileURL()
    defer { tearDownLogFile(fileURL) }

    Container.shared.fakeContinuousClock().freeze()

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000
    )

    for _ in 0..<350 {
      log(handler, message: "storm", line: 1)
    }

    let entries = try decodedEntries(at: fileURL)
    #expect(entries.count == 50)
    #expect(entries.allSatisfy { $0.message == "storm" })
    #expect(entries.allSatisfy { $0.line == 1 })
  }

  @Test("rate limit emits a suppression summary when a throttled site resumes")
  func rateLimitEmitsSuppressionSummaryAfterRefill() throws {
    let fileURL = tempFileURL()
    defer { tearDownLogFile(fileURL) }

    let fakeClock = Container.shared.fakeContinuousClock()
    fakeClock.freeze()

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000
    )

    for _ in 0..<350 {
      log(handler, message: "storm", line: 1)
    }

    fakeClock.advance(by: .seconds(1))
    log(handler, message: "after-refill", line: 1)

    let entries = try decodedEntries(at: fileURL)
    #expect(
      entries.contains {
        $0.message
          == "FileLogHandler rate limit — dropped 300 repeated entries from this log site"
      }
    )
    #expect(entries.last?.message == "after-refill")
  }

  @Test("flush emits pending suppression summaries for quiet throttled sites")
  func flushEmitsPendingSuppressionSummary() throws {
    let fileURL = tempFileURL()
    defer { tearDownLogFile(fileURL) }

    Container.shared.fakeContinuousClock().freeze()

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000
    )

    for _ in 0..<350 {
      log(handler, message: "storm", line: 1)
    }

    FileLogHandler.flush(fileURL: fileURL)

    let entries = try decodedEntries(at: fileURL)
    #expect(entries.count == 51)
    #expect(entries.filter { $0.message == "storm" }.count == 50)
    #expect(
      entries.contains {
        $0.message
          == "FileLogHandler rate limit — dropped 300 repeated entries from this log site"
      }
    )
  }

  @Test("rate limit bounds total volume across many distinct log sites")
  func rateLimitBoundsManyDistinctSites() throws {
    let fileURL = tempFileURL()
    defer { tearDownLogFile(fileURL) }

    Container.shared.fakeContinuousClock().freeze()

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000
    )

    let siteCount = 200
    let logsPerSite = 100
    for line in 1...siteCount {
      for _ in 0..<logsPerSite {
        log(handler, message: "storm-\(line)", line: UInt(line))
      }
    }
    FileLogHandler.flush(fileURL: fileURL)

    let entries = try decodedEntries(at: fileURL)
    #expect(entries.count == siteCount * 51)
    for sampleLine in [1, 50, 100, 150, 200] {
      #expect(entries.filter { $0.message == "storm-\(sampleLine)" }.count == 50)
    }
  }

  @Test("two handlers for the same file share one writer and rate limit bucket")
  func twoHandlersShareWriterPerFileURL() throws {
    let fileURL = tempFileURL()
    defer { tearDownLogFile(fileURL) }

    Container.shared.fakeContinuousClock().freeze()

    let handlerA = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000
    )
    let handlerB = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000
    )

    for _ in 0..<200 {
      log(handlerA, message: "storm", line: 1)
      log(handlerB, message: "storm", line: 1)
    }
    FileLogHandler.flush(fileURL: fileURL)

    let entries = try decodedEntries(at: fileURL)
    #expect(entries.filter { $0.message == "storm" }.count == 50)
    #expect(
      entries.contains {
        $0.message
          == "FileLogHandler rate limit — dropped 350 repeated entries from this log site"
      }
    )
  }

  @Test("rate limit is keyed per (file, line) — different files do not interfere")
  func rateLimitIsKeyedPerFile() throws {
    let fileURL = tempFileURL()
    defer { tearDownLogFile(fileURL) }

    Container.shared.fakeContinuousClock().freeze()

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000
    )

    for _ in 0..<200 { log(handler, message: "site-a", file: "A.swift", line: 1) }
    for _ in 0..<200 { log(handler, message: "site-b", file: "B.swift", line: 1) }

    let entries = try decodedEntries(at: fileURL)
    #expect(entries.filter { $0.message == "site-a" }.count == 50)
    #expect(entries.filter { $0.message == "site-b" }.count == 50)
  }

  @Test("rate limit is keyed per (file, line) — different lines do not interfere")
  func rateLimitIsKeyedPerSite() throws {
    let fileURL = tempFileURL()
    defer { tearDownLogFile(fileURL) }

    Container.shared.fakeContinuousClock().freeze()

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000
    )

    for _ in 0..<200 { log(handler, message: "site-1", line: 1) }
    for _ in 0..<200 { log(handler, message: "site-2", line: 2) }

    let entries = try decodedEntries(at: fileURL)
    #expect(entries.filter { $0.line == 1 }.count == 50)
    #expect(entries.filter { $0.line == 2 }.count == 50)
  }

  @Test("truncation forces cut when no newline exists from cut point to EOF")
  func truncationForcesCutWithoutNewlineBoundary() throws {
    let fileURL = tempFileURL()
    defer { tearDownLogFile(fileURL) }

    let maxFileSizeBytes = 50_000
    let targetFileSizeBytes = 30_000

    var data = Data()
    let padding = String(repeating: "a", count: 80)
    for index in 0..<400 {
      let line = "{\"message\":\"entry-\(index)-\(padding)\",\"line\":\(index)}\n"
      data.append(Data(line.utf8))
    }
    data.append(Data(repeating: 0x78, count: 25_000))

    try data.write(to: fileURL)

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: maxFileSizeBytes,
      targetFileSizeBytes: targetFileSizeBytes
    )
    log(handler, message: "trigger-truncate", line: 999)

    let fileSize = try Data(contentsOf: fileURL).count
    #expect(fileSize <= maxFileSizeBytes)

    let lines = String(decoding: try Data(contentsOf: fileURL), as: UTF8.self)
      .split(separator: "\n", omittingEmptySubsequences: true)
    #expect(lines.contains { $0.contains("trigger-truncate") })
  }

  @Test("async writes are timestamped at log-call time, not when the queue drains")
  func asyncWriteTimestampsAtCallTime() throws {
    let fileURL = tempFileURL()
    defer { tearDownLogFile(fileURL) }

    let fakeDate = Container.shared.fakeDate()
    fakeDate.freeze(at: Date(timeIntervalSince1970: 1_000))

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000,
      synchronous: false
    )

    log(handler, message: "deferred", line: 1)
    // The writer queue drains during flush(); advancing the wall clock first
    // proves the entry is stamped when log() was called (1_000), not when the
    // entry is later built on the queue (2_000).
    fakeDate.freeze(at: Date(timeIntervalSince1970: 2_000))
    FileLogHandler.flush(fileURL: fileURL)

    let entries = try decodedEntries(at: fileURL)
    #expect(entries.count == 1)
    #expect(entries.first?.timestamp == 1_000_000)
  }

  @Test("asynchronous writes reach the file once flushed")
  func asynchronousWritesReachFileOnceFlushed() throws {
    let fileURL = tempFileURL()
    defer { tearDownLogFile(fileURL) }

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000,
      synchronous: false
    )

    for index in 0..<10 {
      log(handler, message: "entry-\(index)", line: UInt(index))
    }
    FileLogHandler.flush(fileURL: fileURL)
    for index in 10..<20 {
      log(handler, message: "entry-\(index)", line: UInt(index))
    }
    FileLogHandler.flush(fileURL: fileURL)

    let entries = try decodedEntries(at: fileURL)
    #expect(entries.map(\.message) == (0..<20).map { "entry-\($0)" })
  }

  @Test("async truncation completes after scoped flush without blocking")
  func asyncTruncationCompletesAfterScopedFlush() throws {
    let fileURL = tempFileURL()
    defer { tearDownLogFile(fileURL) }

    let maxFileSizeBytes = 200_000
    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: maxFileSizeBytes,
      targetFileSizeBytes: 130_000,
      synchronous: false
    )

    let written = 1_000
    let padding = String(repeating: "x", count: 120)
    for index in 0..<written {
      log(
        handler,
        message: "entry-\(String(format: "%04d", index))-\(padding)",
        line: UInt(index)
      )
    }
    FileLogHandler.flush(fileURL: fileURL)

    let fileSize = try Data(contentsOf: fileURL).count
    #expect(fileSize <= maxFileSizeBytes)

    let entries = try decodedEntries(at: fileURL)
    #expect(!entries.isEmpty)
    #expect(entries.count < written)

    let firstIndex = try #require(entries.first.map { Int($0.line) })
    #expect(entries.map { Int($0.line) } == Array(firstIndex..<written))
    #expect(entries.last?.message == "entry-\(String(format: "%04d", written - 1))-\(padding)")
  }
}
