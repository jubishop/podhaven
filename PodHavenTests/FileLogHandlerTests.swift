// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import Testing

@testable import PodHaven

@Suite("of FileLogHandler tests", .container)
struct FileLogHandlerTests {
  // swift-log's `Logger` captures its `LogHandler` at construction time, and
  // `FileLogHandler.Writer.log` is a `static let` that lazy-initializes on
  // its first emit. Bootstrapping the capture handler in suite `init()`
  // guarantees the logger captures our multiplex no matter which test in
  // the suite runs first under concurrent execution.
  init() {
    LogCapture.installOnce()
  }

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

  // Returns the suppressed-entry counts emitted by FileLogHandler's
  // suppression-summary path, in file order.
  private func suppressionSummaries(at fileURL: URL) throws -> [Int] {
    try decodedEntries(at: fileURL)
      .compactMap { entry in
        guard
          let range = entry.message.range(
            of: #"FileLogHandler rate limit — dropped (\d+) repeated"#,
            options: .regularExpression
          )
        else { return nil }
        let match = entry.message[range]
        let digits = match.split(whereSeparator: { !$0.isNumber }).joined()
        return Int(digits)
      }
  }

  // Filters captured warnings down to ones produced by a specific storming
  // call site, identified by the unique `line` value the test used. This is
  // how concurrent tests pick their own warnings out of the process-wide
  // capture buffer without having to clear it.
  private func stormWarnings(forStormingLine line: UInt) -> [LogCapture.Captured] {
    LogCapture.captured()
      .filter { captured in
        captured.label == "PodHaven/FileLogWriter"
          && captured.level == .warning
          && captured.message.contains("FileLogHandlerTests.swift:\(line) ")
      }
  }

  @Test("writes each entry as its own newline-delimited JSON line")
  func writesEntriesAsNewlineDelimitedJSON() throws {
    let fileURL = tempFileURL()
    defer { try? FileManager.default.removeItem(at: fileURL) }

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
    defer { try? FileManager.default.removeItem(at: fileURL) }

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
    defer { try? FileManager.default.removeItem(at: fileURL) }

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

  @Test("rate limit drops storming entries at one site after the burst is spent")
  func rateLimitDropsStormingEntries() throws {
    let fileURL = tempFileURL()
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000
    )

    // 50 fills the burst at line=1; the remaining 300 all drop because the
    // fake clock doesn't advance, so the token bucket can't refill. Covers
    // the drop accounting and per-site bucket creation; storm-warning
    // emission is covered by the dedicated tests below.
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
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000
    )

    // Burst the bucket at line=1, then storm line=2; line=2's bucket is
    // independent so its first 50 still write through.
    for _ in 0..<200 { log(handler, message: "site-1", line: 1) }
    for _ in 0..<200 { log(handler, message: "site-2", line: 2) }

    let entries = try decodedEntries(at: fileURL)
    #expect(entries.filter { $0.line == 1 }.count == 50)
    #expect(entries.filter { $0.line == 2 }.count == 50)
  }

  @Test("storm-warning trigger engages after enough drops and a clock advance")
  func stormWarningTriggerEngagesAfterDropsAndClockAdvance() throws {
    let fileURL = tempFileURL()
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000
    )
    let storming: UInt = 10_001

    // Burn the burst (50) + 250 drops at one site. With the fake clock
    // frozen, no token refills, so all 250 are suppressed.
    for _ in 0..<300 {
      log(handler, message: "storm", line: storming)
    }

    // Advance past one token's worth of refill. The next emit succeeds
    // and should be preceded by a suppression-summary line in the file.
    Container.shared.fakeContinuousClock().advance(by: .seconds(2))
    log(handler, message: "released", line: storming)

    let summaries = try suppressionSummaries(at: fileURL)
    #expect(summaries.contains { 240...260 ~= $0 })
  }

  @Test("storm warning is emitted via Self.log.warning with the originating site")
  func stormWarningEmittedWithOriginatingSite() throws {
    let fileURL = tempFileURL()
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000
    )
    let storming: UInt = 10_002

    for _ in 0..<300 {
      log(handler, message: "storm", line: storming)
    }
    Container.shared.fakeContinuousClock().advance(by: .seconds(2))
    log(handler, message: "released", line: storming)

    let warnings = stormWarnings(forStormingLine: storming)
    #expect(warnings.count == 1)
    let warning = try #require(warnings.first)
    #expect(warning.label == "PodHaven/FileLogWriter")
    #expect(warning.level == .warning)
    #expect(warning.message.contains("FileLogHandler storm:"))
    #expect(warning.message.contains("FileLogHandlerTests.swift:\(storming) in test()"))
    #expect(warning.message.contains("suppressed 250"))
  }

  @Test("storm warning carries a captured call stack from the originating thread")
  func stormWarningCarriesCallStack() throws {
    let fileURL = tempFileURL()
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000
    )
    let storming: UInt = 10_003

    for _ in 0..<300 {
      log(handler, message: "storm", line: storming)
    }
    Container.shared.fakeContinuousClock().advance(by: .seconds(2))
    log(handler, message: "released", line: storming)

    let warning = try #require(stormWarnings(forStormingLine: storming).first)
    #expect(warning.message.contains("Stack:"))
    // FileLogHandler.log is the dispatch site that captures the stack;
    // pinning a frame from the production code keeps the test stable
    // across runs of the test binary's mangled symbol names.
    #expect(warning.message.contains("FileLogHandler"))
  }

  @Test("per-bucket cooldown blocks a second warning within 60 seconds at the same site")
  func cooldownBlocksSecondWarningAtSameSite() throws {
    let fileURL = tempFileURL()
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000
    )
    let storming: UInt = 10_004
    let clock = Container.shared.fakeContinuousClock()

    for _ in 0..<300 { log(handler, message: "storm", line: storming) }
    clock.advance(by: .seconds(2))
    log(handler, message: "released-1", line: storming)

    // Storm again 30s later — token refilled, threshold met, but cooldown
    // (60s) blocks the second warning.
    for _ in 0..<300 { log(handler, message: "storm", line: storming) }
    clock.advance(by: .seconds(30))
    log(handler, message: "released-2", line: storming)

    #expect(stormWarnings(forStormingLine: storming).count == 1)

    // Past the 60s cooldown the next storm releases another warning.
    for _ in 0..<300 { log(handler, message: "storm", line: storming) }
    clock.advance(by: .seconds(60))
    log(handler, message: "released-3", line: storming)

    #expect(stormWarnings(forStormingLine: storming).count == 2)
  }

  @Test("cooldown is per-bucket — a second site warns independently")
  func cooldownIsPerBucket() throws {
    let fileURL = tempFileURL()
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000
    )
    let siteA: UInt = 10_005
    let siteB: UInt = 10_006
    let clock = Container.shared.fakeContinuousClock()

    for _ in 0..<300 { log(handler, message: "site-a", line: siteA) }
    for _ in 0..<300 { log(handler, message: "site-b", line: siteB) }
    clock.advance(by: .seconds(2))

    log(handler, message: "released-a", line: siteA)
    log(handler, message: "released-b", line: siteB)

    #expect(stormWarnings(forStormingLine: siteA).count == 1)
    #expect(stormWarnings(forStormingLine: siteB).count == 1)
  }

  @Test("asynchronous writes reach the file once flushed")
  func asynchronousWritesReachFileOnceFlushed() throws {
    let fileURL = tempFileURL()
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let handler = makeHandler(
      fileURL: fileURL,
      maxFileSizeBytes: 10_000_000,
      targetFileSizeBytes: 5_000_000,
      synchronous: false
    )

    // flush() drains the queue and closes the append handle; the second
    // batch then exercises reopening it.
    for index in 0..<10 {
      log(handler, message: "entry-\(index)", line: UInt(index))
    }
    FileLogHandler.flush()
    for index in 10..<20 {
      log(handler, message: "entry-\(index)", line: UInt(index))
    }
    FileLogHandler.flush()

    let entries = try decodedEntries(at: fileURL)
    #expect(entries.map(\.message) == (0..<20).map { "entry-\($0)" })
  }
}
