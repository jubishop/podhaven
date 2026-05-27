// Copyright Justin Bishop, 2026

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
    // The threshold sits below the per-cycle drop count of any sustained
    // storm (with a 1/sec refill, drops/cycle ≈ rate − 1), so a site
    // exceeding ~26/sec gets flagged on its next successful emit.
    private static let rateLimitWarningThreshold = 25
    private static let rateLimitWarningCooldownMs: Int64 = 60_000

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
      callStack: [String]?,
      synchronously: Bool
    ) {
      if synchronously {
        let results = queue.sync { writeEntry(entry, decision: decision, callStack: callStack) }
        for result in results { report(result) }
      } else {
        queue.async {
          let results = self.writeEntry(entry, decision: decision, callStack: callStack)
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
      case stormWarning(entry: Entry, suppressed: Int, callStack: [String]?)
      case failed(any Error)
    }

    // Must be called on `queue`. Returns every result this write produced —
    // truncation and a storm warning can both fire on the same call, and
    // collapsing them into a single return would drop one (and silently
    // burn the storm-warning cooldown for 60s).
    private func writeEntry(
      _ entry: Entry,
      decision: RateLimitDecision,
      callStack: [String]?
    ) -> [WriteResult] {
      guard case .write(let suppressed, let shouldWarn) = decision else { return [] }
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
        if shouldWarn {
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
        let stackText = callStack?.joined(separator: "\n") ?? "(not captured)"
        Self.log.warning(
          """
          FileLogHandler storm: \(entry.file):\(entry.line) in \(entry.function) — \
          suppressed \(suppressed) entries since last emit. Stack:
          \(stackText)
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
      var lastRefillMs: Int64
      var suppressedCount: Int
      var lastWarningMs: Int64
    }

    enum RateLimitDecision {
      case write(suppressed: Int, shouldWarn: Bool)
      case drop
    }

    // Commits the bucket update atomically and returns the decision the caller
    // must honor: drop the entry, or write it (optionally promoted to a storm
    // warning). Called from the log path before any queue dispatch so the
    // storm-warn flag and the originating thread's `Thread.callStackSymbols`
    // are captured in the same synchronous step — a later peek on the writer
    // queue could otherwise see a stale `suppressedCount` and miss the stack.
    func commitRateLimitDecision(for entry: Entry) -> RateLimitDecision {
      let key = RateKey(file: entry.file, line: entry.line)
      let now = entry.timestamp
      return rateLimitBuckets { buckets in
        var bucket =
          buckets[key]
          ?? RateBucket(
            tokens: Self.rateLimitBurst,
            lastRefillMs: now,
            suppressedCount: 0,
            lastWarningMs: 0
          )
        let elapsedMs = max(0, now - bucket.lastRefillMs)
        bucket.tokens = min(
          Self.rateLimitBurst,
          bucket.tokens + Double(elapsedMs) / 1000 * Self.rateLimitTokensPerSecond
        )
        bucket.lastRefillMs = now

        let decision: RateLimitDecision
        if bucket.tokens >= 1 {
          bucket.tokens -= 1
          let suppressed = bucket.suppressedCount
          bucket.suppressedCount = 0
          let shouldWarn =
            suppressed >= Self.rateLimitWarningThreshold
            && now - bucket.lastWarningMs >= Self.rateLimitWarningCooldownMs
          if shouldWarn { bucket.lastWarningMs = now }
          decision = .write(suppressed: suppressed, shouldWarn: shouldWarn)
        } else {
          bucket.suppressedCount += 1
          decision = .drop
        }
        buckets[key] = bucket
        return decision
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

    let decision = writer.commitRateLimitDecision(for: entry)
    guard case .write(_, let shouldWarn) = decision else { return }
    let callStack: [String]? = shouldWarn ? Thread.callStackSymbols : nil
    writer.write(
      entry,
      decision: decision,
      callStack: callStack,
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
