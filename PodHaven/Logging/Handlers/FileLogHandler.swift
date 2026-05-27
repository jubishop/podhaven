// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import os

struct FileLogHandler: LogHandler {
  // MARK: - Writer

  fileprivate final class Writer: Sendable {
    private static let log = Log.as("FileLogWriter")
    private static let fallbackLog = os.Logger(subsystem: "PodHaven", category: "FileLogWriter")

    private static let truncationWindowBytes = 64 * 1024

    // Per-call-site rate limit. A runaway log site (e.g. a tight observation
    // loop) can otherwise fill the whole rolling buffer in seconds, evicting
    // the history that explains how the runaway began. Each call site gets a
    // token bucket; once it is spent, further entries are dropped and counted,
    // and the next entry that gets through is preceded by a one-line summary.
    private static let rateLimitBurst = 50.0
    private static let rateLimitTokensPerSecond = 1.0

    // Storm warning. When a single call site has dropped this many entries
    // between successful emits, we promote the next emit's report to a
    // `.warning` carrying the site's file/line/function and the originating
    // call stack — so storms surface in Sentry within ~1s of starting,
    // without needing a Sentry feedback to triage. Per-bucket cooldown
    // prevents the warning itself from storming during a sustained event.
    // With 1 token/sec refill, a sustained rate R/sec produces R−1 drops
    // per successful emit. Threshold 25 means any sustained site at
    // ≥ 26/sec surfaces on its next successful emit; lighter cadences
    // stay quiet.
    private static let rateLimitWarningThreshold = 25
    private static let rateLimitWarningCooldown: Duration = .seconds(60)

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
      closeAppendHandle()
    }

    func write(
      _ entry: Entry,
      decision: RateLimitDecision,
      synchronously: Bool
    ) {
      if synchronously {
        let results = queue.sync { writeEntry(entry, decision: decision) }
        for result in results { report(result) }
      } else {
        queue.async {
          let results = self.writeEntry(entry, decision: decision)
          Task { [weak self] in
            guard let self else { return }
            for result in results { report(result) }
          }
        }
      }
    }

    func flush() {
      queue.sync { closeAppendHandle() }
    }

    private enum WriteResult {
      case message(String)
      case stormWarning(entry: Entry, suppressed: Int, callStack: [String])
      case failed(any Error)
    }

    // Must be called on `queue`. Returns every result this write produced —
    // truncation and a storm warning can both fire on the same call, and
    // collapsing them into a single return would drop one (and silently
    // burn the storm-warning cooldown for 60s).
    private func writeEntry(
      _ entry: Entry,
      decision: RateLimitDecision
    ) -> [WriteResult] {
      guard case .write(let suppressed, let callStack) = decision else { return [] }
      do {
        // The real entry is always appended right after, and appendEntry
        // returns the post-write file size — so the single truncation check
        // below already accounts for this summary line's bytes too.
        if suppressed > 0 {
          try appendEntry(suppressionSummary(for: entry, suppressed: suppressed))
        }
        let currentSize = try appendEntry(entry)
        var results: [WriteResult] = []
        if currentSize > UInt64(maxFileSizeBytes) {
          if let truncation = try truncateIfNeeded() {
            results.append(
              .message(
                "Log truncated from \(truncation.originalSize) to \(truncation.newSize) bytes"
              )
            )
          }
        }
        if let callStack {
          results.append(.stormWarning(entry: entry, suppressed: suppressed, callStack: callStack))
        }
        return results
      } catch {
        return [.failed(error)]
      }
    }

    // Must be called outside `queue` (or asynchronously) to avoid deadlock.
    private func report(_ result: WriteResult) {
      switch result {
      case .message(let message):
        Self.log.info("\(message)")
      case .stormWarning(let entry, let suppressed, let callStack):
        Self.log.warning(
          """
          FileLogHandler storm: \(entry.file):\(entry.line) in \(entry.function) — \
          suppressed \(suppressed) entries since last emit. Stack:
          \(callStack.joined(separator: "\n"))
          """
        )
      case .failed(let error):
        Self.fallbackLog.error(
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
        fallbackLog.error(
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

      // Cut on a newline boundary; truncating mid-line would corrupt the log.
      guard let cutOffset = try Self.firstNewlineOffset(in: reader, atOrAfter: bytesToRemove)
      else { return nil }

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
          Self.fallbackLog.error(
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

    private struct RateKey: Hashable {
      let file: String
      let line: UInt
    }

    private struct RateBucket {
      var tokens: Double
      var lastRefill: ContinuousClock.Instant
      var suppressedCount: Int
      // nil sentinel = never warned; first threshold crossing always passes
      // the cooldown gate.
      var lastWarning: ContinuousClock.Instant?
    }

    fileprivate enum RateLimitDecision {
      // `callStack` non-nil iff this emit is promoted to a storm warning;
      // captured by the log path on the originating thread *outside* the
      // bucket mutex (see `commitRateLimitDecision` doc).
      case write(suppressed: Int, callStack: [String]?)
      case drop
    }

    // Commits the bucket update atomically and returns the decision the caller
    // must honor: drop the entry, or write it (optionally promoted to a storm
    // warning carrying `callStack`). Called from the log path before any
    // queue dispatch so the warning decision and the originating thread's
    // `Thread.callStackSymbols` are observed in the same synchronous step.
    //
    // Lock scope: bucket bookkeeping (refill, token spend, suppressed reset,
    // `lastWarning` advance) commits inside the rate-limit mutex; the
    // `captureCallStack` autoclosure is invoked *after* the mutex is
    // released, on the originating thread. Stack symbolication is
    // multi-millisecond; running it under the mutex would serialize every
    // log call across the app during a storm — exactly the regression
    // mode this feature is meant to surface, not introduce. The cooldown
    // is committed before the autoclosure runs, so a concurrent log call
    // racing the stack walk sees the cooldown already in effect and
    // doesn't double-warn.
    //
    // `captureCallStack` is an autoclosure invoked only when the bucket
    // crosses the warning threshold (cost is a per-cooldown per-site upper
    // bound, not a per-log-call cost).
    //
    // Must be called exactly once per `LogEvent`, from the log call path
    // (not the writer queue). Each successful call spends a token; calling
    // twice would double-charge. The mutex is taken on the caller's thread,
    // including the main thread; hold time is microseconds.
    func commitRateLimitDecision(
      for entry: Entry,
      captureCallStack: @autoclosure () -> [String]
    ) -> RateLimitDecision {
      let key = RateKey(file: entry.file, line: entry.line)
      let now = Container.shared.continuousClockNow()()

      // Phase 1 (under mutex): commit all bucket bookkeeping including the
      // cooldown advance. Returns the bare facts; no stack capture yet.
      enum Pending {
        case write(suppressed: Int, shouldCaptureCallStack: Bool)
        case drop
      }

      let pending: Pending = rateLimitBuckets { buckets in
        var bucket =
          buckets[key]
          ?? RateBucket(
            tokens: Self.rateLimitBurst,
            lastRefill: now,
            suppressedCount: 0,
            lastWarning: nil
          )
        let elapsed = now - bucket.lastRefill
        let elapsedSeconds = max(
          0,
          Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
        )
        bucket.tokens = min(
          Self.rateLimitBurst,
          bucket.tokens + elapsedSeconds * Self.rateLimitTokensPerSecond
        )
        bucket.lastRefill = now

        let pending: Pending
        if bucket.tokens >= 1 {
          bucket.tokens -= 1
          let suppressed = bucket.suppressedCount
          bucket.suppressedCount = 0
          let cooledDown: Bool
          if let lastWarning = bucket.lastWarning {
            cooledDown = now - lastWarning >= Self.rateLimitWarningCooldown
          } else {
            cooledDown = true
          }
          let shouldWarn = suppressed >= Self.rateLimitWarningThreshold && cooledDown
          if shouldWarn { bucket.lastWarning = now }
          pending = .write(suppressed: suppressed, shouldCaptureCallStack: shouldWarn)
        } else {
          bucket.suppressedCount += 1
          pending = .drop
        }
        buckets[key] = bucket
        return pending
      }

      // Phase 2 (outside mutex): walk the stack on the originating thread
      // only when the bucket said so.
      switch pending {
      case .drop:
        return .drop
      case .write(let suppressed, let shouldCaptureCallStack):
        let callStack: [String]? = shouldCaptureCallStack ? captureCallStack() : nil
        return .write(suppressed: suppressed, callStack: callStack)
      }
    }

    private func suppressionSummary(for entry: Entry, suppressed: Int) -> Entry {
      Entry(
        level: Logging.Logger.Level.info.intValue,
        levelName: Logging.Logger.Level.info.rawValue,
        timestamp: entry.timestamp,
        subsystem: entry.subsystem,
        category: entry.category,
        message:
          "FileLogHandler rate limit — dropped \(suppressed) repeated entries from this log site",
        metadata: nil,
        source: entry.source,
        file: entry.file,
        function: entry.function,
        line: entry.line
      )
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
    let mergedMetadata = LogKit.merge(
      handler: self.metadata,
      provider: self.metadataProvider,
      oneOff: event.metadata
    )

    let entry = Entry(
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

    let decision = writer.commitRateLimitDecision(
      for: entry,
      captureCallStack: Thread.callStackSymbols
    )
    guard case .write = decision else { return }
    writer.write(
      entry,
      decision: decision,
      synchronously: writeSynchronously(event.level)
    )
  }

  // MARK: - Flush

  static func flush() {
    for writer in writers().values {
      writer.flush()
    }
  }
}
