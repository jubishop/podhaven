// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import os

struct FileLogHandler: LogHandler {
  // MARK: - Writer

  fileprivate final class Writer: Sendable {
    // Writer I/O failures and housekeeping (truncation notice, close errors).
    // OSLog only — never NDJSON; swift-log would re-enter this handler's queue.
    private static let writerOSLog = os.Logger(subsystem: "PodHaven", category: "FileLogWriter")

    private static let truncationWindowBytes = 64 * 1024

    // Per-call-site rate limit. A runaway log site (e.g. a tight observation
    // loop) can otherwise fill the whole rolling buffer in seconds, evicting
    // the history that explains how the runaway began. Each call site gets a
    // token bucket; once it is spent, further entries are dropped and counted,
    // and the next entry that gets through is preceded by a one-line summary.
    private static let rateLimitBurst = 50.0
    private static let rateLimitTokensPerSecond = 1.0

    // Buckets are never evicted: one entry per distinct (file, line) for the
    // Writer lifetime. That is acceptable — typical site count stays modest
    // relative to log volume, and flush only iterates sites with pending drops.

    let fileURL: URL
    let maxFileSizeBytes: Int
    let targetFileSizeBytes: Int
    private let queue: DispatchQueue
    private let rateLimitBuckets = ThreadSafe<[RateKey: RateBucket]>([:])

    private let encoder = ThreadSafe(JSONEncoder())

    // Reused across writes; closed and reopened around truncation's inode swap.
    private let appendHandle = ThreadSafe<FileHandle?>(nil)

    init(fileURL: URL, maxFileSizeBytes: Int, targetFileSizeBytes: Int) {
      self.fileURL = fileURL
      self.maxFileSizeBytes = maxFileSizeBytes
      self.targetFileSizeBytes = targetFileSizeBytes
      let fileName = fileURL.deletingPathExtension().lastPathComponent
      self.queue = DispatchQueue(
        label: "\(AppInfo.bundleIdentifier).FileLogHandler.Writer.\(fileName)",
        qos: .background
      )
    }

    deinit {
      queue.sync { closeAppendHandle() }
    }

    func log(
      file: String,
      line: UInt,
      synchronously: Bool,
      makeEntry: @escaping @Sendable () -> Entry
    ) {
      let work: @Sendable () -> Void = { [weak self] in
        guard let self else { return }
        switch self.rateLimitDecision(file: file, line: line) {
        case .drop:
          return
        case .write:
          let result = self.writeEntry(makeEntry())
          Self.emitOSLogOnly(result)
        }
      }
      if synchronously {
        queue.sync(execute: work)
      } else {
        queue.async(execute: work)
      }
    }

    // Must be called on `queue`.
    private func rateLimitDecision(file: String, line: UInt) -> RateLimitDecision {
      let now = Container.shared.continuousClockNow()()
      let key = RateKey(file: file, line: line)
      return rateLimitBuckets { buckets in
        var bucket =
          buckets[key]
          ?? RateBucket(
            tokens: Self.rateLimitBurst,
            lastRefill: now,
            suppressedCount: 0,
            lastContext: nil
          )
        let elapsedSeconds = Self.secondsBetween(bucket.lastRefill, now)
        bucket.tokens = min(
          Self.rateLimitBurst,
          bucket.tokens + elapsedSeconds * Self.rateLimitTokensPerSecond
        )
        bucket.lastRefill = now

        let decision: RateLimitDecision
        if bucket.tokens >= 1 {
          bucket.tokens -= 1
          decision = .write
        } else {
          bucket.suppressedCount += 1
          decision = .drop
        }
        buckets[key] = bucket
        return decision
      }
    }

    func flush() {
      let result = queue.sync {
        let pending = flushPendingSuppressions()
        closeAppendHandle()
        return pending
      }
      Self.emitOSLogOnly(result)
    }

    private enum WriteResult {
      case ok
      case message(String)
      case failed(any Error)
    }

    // Must be called on `queue`.
    private func writeEntry(_ entry: Entry) -> WriteResult {
      recordContext(for: entry)
      let key = RateKey(file: entry.file, line: entry.line)
      let suppressed = pendingSuppressedCount(for: key)
      do {
        // The real entry is always appended right after, and appendEntry
        // returns the post-write file size — so the single truncation check
        // below already accounts for this summary line's bytes too.
        if suppressed > 0 {
          try appendEntry(
            suppressionSummary(
              context: SuppressionContext.from(entry: entry),
              suppressed: suppressed
            )
          )
          clearSuppressedCount(for: key)
        }
        let currentSize = try appendEntry(entry)
        guard currentSize > UInt64(maxFileSizeBytes) else { return .ok }
        guard let truncation = try truncateIfNeeded() else { return .ok }
        return .message(
          "Log truncated from \(truncation.originalSize) to \(truncation.newSize) bytes"
        )
      } catch {
        return .failed(error)
      }
    }

    private static func emitOSLogOnly(_ result: WriteResult) {
      switch result {
      case .ok:
        break
      case .message(let message):
        Self.writerOSLog.info("\(message, privacy: .public)")
      case .failed(let error):
        Self.writerOSLog.error(
          "Failed to write log entry: \(error.localizedDescription, privacy: .public)"
        )
      }
    }

    @discardableResult
    private func appendEntry(_ entry: Entry) throws -> UInt64 {
      var data = try encoder { try $0.encode(entry) }
      data.append(0x0A)

      return try appendHandle { handle in
        let writeHandle = try handle ?? Self.openForAppending(at: fileURL)
        handle = writeHandle
        try writeHandle.write(contentsOf: data)
        return try writeHandle.offset()
      }
    }

    private static func openForAppending(at fileURL: URL) throws -> FileHandle {
      if !FileManager.default.fileExists(atPath: fileURL.path) {
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
      }
      let handle = try FileHandle(forWritingTo: fileURL)
      _ = try handle.seekToEnd()
      return handle
    }

    private func closeAppendHandle() {
      appendHandle { handle in
        if let openHandle = handle {
          Self.close(openHandle)
        }
        handle = nil
      }
    }

    private static func close(_ handle: FileHandle) {
      do {
        try handle.close()
      } catch {
        writerOSLog.error(
          "Failed to close log file handle: \(error.localizedDescription, privacy: .public)"
        )
      }
    }

    // Windowed scan so the whole file is never read into memory at once.
    private static func firstNewlineOffset(
      in reader: FileHandle,
      atOrAfter start: Int
    ) throws -> UInt64? {
      try reader.seek(toOffset: UInt64(start))
      var offset = UInt64(start)
      while let window = try reader.read(upToCount: truncationWindowBytes), !window.isEmpty {
        if let newlineIndex = window.firstIndex(of: 0x0A) {
          return offset + UInt64(window.distance(from: window.startIndex, to: newlineIndex)) + 1
        }
        offset += UInt64(window.count)
      }
      return nil
    }

    private func truncateIfNeeded() throws -> (originalSize: Int, newSize: Int)? {
      let reader = try FileHandle(forReadingFrom: fileURL)
      defer { Self.close(reader) }

      let fileSize = try reader.seekToEnd()
      guard fileSize > UInt64(maxFileSizeBytes) else { return nil }

      let bytesToRemove = Int(fileSize) - targetFileSizeBytes
      guard bytesToRemove > 0 else { return nil }

      let cutOffset: UInt64
      if let newlineOffset = try Self.firstNewlineOffset(in: reader, atOrAfter: bytesToRemove) {
        cutOffset = newlineOffset
      } else {
        Self.writerOSLog.warning(
          "Log truncation found no newline boundary; forcing cut at byte offset \(bytesToRemove, privacy: .public)"
        )
        cutOffset = UInt64(bytesToRemove)
      }

      // Atomic swap so a crash mid-rewrite can't leave a corrupt log.
      let tempURL = fileURL.deletingLastPathComponent()
        .appendingPathComponent("truncate-\(UUID().uuidString)")
      do {
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let writer = try FileHandle(forWritingTo: tempURL)
        defer { Self.close(writer) }
        try reader.seek(toOffset: cutOffset)
        while let chunk = try reader.read(upToCount: Self.truncationWindowBytes), !chunk.isEmpty {
          try writer.write(contentsOf: chunk)
        }
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
      } catch {
        do {
          try FileManager.default.removeItem(at: tempURL)
        } catch CocoaError.fileNoSuchFile {
          // Temp file was never created.
        } catch {
          Self.writerOSLog.error(
            "Failed to remove truncation temp file: \(error.localizedDescription, privacy: .public)"
          )
        }
        throw error
      }

      // The swap gave the file a new inode; drop the now-stale append handle.
      closeAppendHandle()

      return (originalSize: Int(fileSize), newSize: Int(fileSize - cutOffset))
    }

    // MARK: - Rate Limiting

    private enum RateLimitDecision {
      case write
      case drop
    }

    private struct RateKey: Hashable {
      let file: String
      let line: UInt
    }

    private struct SuppressionContext: Sendable {
      let timestamp: Int64
      let subsystem: String
      let category: String
      let source: String
      let file: String
      let function: String
      let line: UInt

      static func from(entry: Entry) -> SuppressionContext {
        SuppressionContext(
          timestamp: entry.timestamp,
          subsystem: entry.subsystem,
          category: entry.category,
          source: entry.source,
          file: entry.file,
          function: entry.function,
          line: entry.line
        )
      }

      static func fallback(for key: RateKey) -> SuppressionContext {
        SuppressionContext(
          timestamp: Int64(Date().timeIntervalSince1970 * 1000),
          subsystem: "PodHaven",
          category: "FileLogWriter",
          source: "FileLogHandler",
          file: key.file,
          function: "",
          line: key.line
        )
      }
    }

    private struct RateBucket {
      var tokens: Double
      var lastRefill: ContinuousClock.Instant
      var suppressedCount: Int
      var lastContext: SuppressionContext?
    }

    private func recordContext(for entry: Entry) {
      let key = RateKey(file: entry.file, line: entry.line)
      let context = SuppressionContext.from(entry: entry)
      rateLimitBuckets { buckets in
        guard var bucket = buckets[key] else { return }
        bucket.lastContext = context
        buckets[key] = bucket
      }
    }

    private func pendingSuppressedCount(for key: RateKey) -> Int {
      rateLimitBuckets { buckets in
        buckets[key]?.suppressedCount ?? 0
      }
    }

    private func clearSuppressedCount(for key: RateKey) {
      rateLimitBuckets { buckets in
        guard var bucket = buckets[key] else { return }
        bucket.suppressedCount = 0
        buckets[key] = bucket
      }
    }

    // Must be called on `queue`.
    private func flushPendingSuppressions() -> WriteResult {
      let pending: [(RateKey, SuppressionContext, Int)] = rateLimitBuckets { buckets in
        buckets.compactMap { key, bucket in
          guard bucket.suppressedCount > 0 else { return nil }
          let context = bucket.lastContext ?? .fallback(for: key)
          return (key, context, bucket.suppressedCount)
        }
      }

      var failure: WriteResult = .ok
      for (key, context, suppressed) in pending {
        let summary = suppressionSummary(context: context, suppressed: suppressed)
        do {
          try appendEntry(summary)
          clearSuppressedCount(for: key)
        } catch {
          failure = .failed(error)
        }
      }
      return failure
    }

    private func suppressionSummary(context: SuppressionContext, suppressed: Int) -> Entry {
      Entry(
        level: Logging.Logger.Level.info.intValue,
        levelName: Logging.Logger.Level.info.rawValue,
        timestamp: context.timestamp,
        subsystem: context.subsystem,
        category: context.category,
        message:
          "FileLogHandler rate limit — dropped \(suppressed) repeated entries from this log site",
        metadata: nil,
        source: context.source,
        file: context.file,
        function: context.function,
        line: context.line
      )
    }

    private static func secondsBetween(
      _ start: ContinuousClock.Instant,
      _ end: ContinuousClock.Instant
    ) -> Double {
      let duration = end - start
      let components = duration.components
      return Double(components.seconds)
        + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
  }

  // MARK: - Entry

  fileprivate struct Entry: Codable {
    let level: Int
    let levelName: String
    let timestamp: Int64
    let subsystem: String
    let category: String
    let message: String
    let metadata: [String: String]?
    let source: String
    let file: String
    let function: String
    let line: UInt
  }

  // MARK: - LogHandler

  public var metadata: Logging.Logger.Metadata = [:]
  public var metadataProvider: Logging.Logger.MetadataProvider?
  public subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
    get { self.metadata[metadataKey] }
    set(newValue) { self.metadata[metadataKey] = newValue }
  }
  public var logLevel: Logging.Logger.Level = .trace

  // MARK: - State

  // One handler is built per logger label; all must share one Writer per file.
  private static let writers = ThreadSafe<[URL: Writer]>([:])
  private let fileURL: URL
  private let subsystem: String
  private let category: String
  private let writer: Writer
  private let writeSynchronously: @Sendable (Logging.Logger.Level) -> Bool

  // MARK: - Initialization

  init(
    label: String,
    fileURL: URL,
    maxFileSizeBytes: Int,
    targetFileSizeBytes: Int,
    writeSynchronously: @escaping @Sendable (Logging.Logger.Level) -> Bool
  ) {
    let (subsystem, category) = LogKit.destructureLabel(from: label)
    self.fileURL = fileURL
    self.subsystem = subsystem
    self.category = category
    self.writeSynchronously = writeSynchronously

    self.writer = Self.writers { writers in
      if let existing = writers[fileURL] { return existing }
      let writer = Writer(
        fileURL: fileURL,
        maxFileSizeBytes: maxFileSizeBytes,
        targetFileSizeBytes: targetFileSizeBytes
      )
      writers[fileURL] = writer
      return writer
    }
  }

  // MARK: - Logging

  public func log(event: LogEvent) {
    writer.log(
      file: event.file,
      line: event.line,
      synchronously: writeSynchronously(event.level),
      makeEntry: { self.makeEntry(from: event) }
    )
  }

  private func makeEntry(from event: LogEvent) -> Entry {
    let mergedMetadata = LogKit.merge(
      handler: self.metadata,
      provider: self.metadataProvider,
      oneOff: event.metadata
    )

    return Entry(
      level: event.level.intValue,
      levelName: event.level.rawValue,
      timestamp: Int64(Date().timeIntervalSince1970 * 1000),
      subsystem: subsystem,
      category: category,
      message: event.message.description,
      metadata: mergedMetadata.isEmpty
        ? nil
        : Dictionary(uniqueKeysWithValues: mergedMetadata.map { ($0.key, $0.value.description) }),
      source: event.source,
      file: event.file,
      function: event.function,
      line: event.line
    )
  }

  // MARK: - Flush

  static func flush(fileURL: URL) {
    writers()[fileURL]?.flush()
  }

  static func flush() {
    flush(fileURL: AppInfo.logFileURL)
  }
}
