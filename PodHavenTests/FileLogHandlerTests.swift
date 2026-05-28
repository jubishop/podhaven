// Copyright Justin Bishop, 2026

import Foundation
import Logging
import Testing

@testable import PodHaven

@Suite("of FileLogHandler tests")
struct FileLogHandlerTests {
  private struct DecodedEntry: Decodable {
    let message: String
    let line: UInt
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
  private func log(_ handler: FileLogHandler, message: String, line: UInt) {
    handler.log(
      event: LogEvent(
        level: .debug,
        message: "\(message)",
        metadata: nil,
        source: "PodHavenTests",
        file: "FileLogHandlerTests.swift",
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

  @Test("rate limit drops repeated entries at one site after the burst is spent")
  func rateLimitDropsRepeatedEntries() throws {
    let fileURL = tempFileURL()
    defer { tearDownLogFile(fileURL) }

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000
    )

    // 50 fills the burst at line=1; the rest drop because the tight loop does
    // not advance wall-clock timestamps enough to refill the bucket.
    for _ in 0..<350 {
      log(handler, message: "storm", line: 1)
    }

    let entries = try decodedEntries(at: fileURL)
    #expect(entries.count == 50)
    #expect(entries.allSatisfy { $0.message == "storm" })
    #expect(entries.allSatisfy { $0.line == 1 })
  }

  @Test("rate limit is keyed per (file, line) — different lines do not interfere")
  func rateLimitIsKeyedPerSite() throws {
    let fileURL = tempFileURL()
    defer { tearDownLogFile(fileURL) }

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
    handler.flush()
    for index in 10..<20 {
      log(handler, message: "entry-\(index)", line: UInt(index))
    }
    handler.flush()

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
    handler.flush()

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
