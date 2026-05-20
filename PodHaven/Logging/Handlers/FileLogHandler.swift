// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import os

extension Container {
  fileprivate var fileLogWriter: ParameterFactory<(URL, Int, Int), FileLogHandler.Writer> {
    ParameterFactory(self) {
      FileLogHandler.Writer(fileURL: $0.0, maxFileSizeBytes: $0.1, targetFileSizeBytes: $0.2)
    }
    .scope(.cached)
  }
}

struct FileLogHandler: LogHandler {
  // MARK: - Writer

  fileprivate final class Writer: Sendable {
    private static let log = Log.as("FileLogWriter")
    private static let fallbackLog = os.Logger(subsystem: "PodHaven", category: "FileLogWriter")

    // Window size for the streaming reads in truncateIfNeeded, so the whole
    // log file is never resident in memory at once.
    private static let truncationWindowBytes = 64 * 1024

    // Per-call-site rate limit. A runaway log site (e.g. a tight observation
    // loop) can otherwise fill the whole rolling buffer in seconds, evicting
    // the history that explains how the runaway began. Each call site gets a
    // token bucket; once it is spent, further entries are dropped and counted,
    // and the next entry that gets through is preceded by a one-line summary.
    private static let rateLimitBurst = 50.0
    private static let rateLimitTokensPerSecond = 1.0

    let fileURL: URL
    let maxFileSizeBytes: Int
    let targetFileSizeBytes: Int
    private let queue: DispatchQueue
    private let rateLimitBuckets = ThreadSafe<[RateKey: RateBucket]>([:])

    // JSONEncoder is a non-Sendable class, so it cannot be a plain stored
    // property of this Sendable class. Encoding only ever runs on the serial
    // `queue`, so the wrapper's lock is redundant but cheap — and reusing one
    // encoder avoids allocating and configuring a fresh one per log line.
    private let encoder = ThreadSafe(JSONEncoder())

    // A long-lived append handle, opened lazily and reused across log lines so
    // each entry costs a single write syscall instead of open + seek + close.
    // truncateIfNeeded() swaps the file in via a fresh inode, so this handle is
    // closed after every truncation and reopened on the next append.
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

    func write(_ entry: Entry, synchronously: Bool) {
      if synchronously {
        let result = queue.sync { writeEntry(entry) }
        report(result)
      } else {
        queue.async {
          let result = self.writeEntry(entry)
          Task { [weak self] in
            guard let self else { return }
            report(result)
          }
        }
      }
    }

    func flush() {
      queue.sync { closeAppendHandle() }
    }

    private enum WriteResult {
      case ok
      case message(String)
      case failed(any Error)
    }

    // Must be called on `queue`.
    private func writeEntry(_ entry: Entry) -> WriteResult {
      guard case .write(let suppressed) = rateLimitDecision(for: entry) else { return .ok }
      do {
        // The real entry is always appended right after, and appendEntry
        // returns the post-write file size — so the single truncation check
        // below already accounts for this summary line's bytes too.
        if suppressed > 0 {
          try appendEntry(suppressionSummary(for: entry, suppressed: suppressed))
        }
        let currentSize = try appendEntry(entry)
        if currentSize > UInt64(maxFileSizeBytes) {
          if let truncation = try truncateIfNeeded() {
            return .message(
              "Log truncated from \(truncation.originalSize) to \(truncation.newSize) bytes"
            )
          }
        }
        return .ok
      } catch {
        return .failed(error)
      }
    }

    // Must be called outside `queue` (or asynchronously) to avoid deadlock.
    private func report(_ result: WriteResult) {
      switch result {
      case .ok:
        break
      case .message(let message):
        Self.log.info("\(message)")
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

    // Scans forward in fixed windows so the whole file is never read into
    // memory at once. Returns the offset just past the first newline at or
    // after `start`, or nil if there is no newline beyond that point.
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

      // Truncating mid-line would corrupt the log, so cut at the first whole
      // newline boundary at or after the computed offset.
      guard let cutOffset = try Self.firstNewlineOffset(in: reader, atOrAfter: bytesToRemove)
      else { return nil }

      // Stream the surviving tail into a sibling temp file, then swap it in
      // atomically so a crash mid-rewrite can never leave a corrupt log.
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
          // Temp file was never created — nothing to clean up.
        } catch {
          Self.fallbackLog.error(
            "Failed to remove truncation temp file: \(error.localizedDescription, privacy: .public)"
          )
        }
        throw error
      }

      // The atomic swap rebinds the path to a new inode; the cached append
      // handle now points at the orphaned file, so close it and let the next
      // append reopen against the truncated file.
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
    }

    private enum RateLimitDecision {
      case write(suppressed: Int)
      case drop
    }

    // Must be called on `queue`.
    private func rateLimitDecision(for entry: Entry) -> RateLimitDecision {
      let key = RateKey(file: entry.file, line: entry.line)
      let now = entry.timestamp
      return rateLimitBuckets { buckets in
        var bucket =
          buckets[key]
          ?? RateBucket(tokens: Self.rateLimitBurst, lastRefillMs: now, suppressedCount: 0)
        let elapsedMs = max(0, now - bucket.lastRefillMs)
        bucket.tokens = min(
          Self.rateLimitBurst,
          bucket.tokens + Double(elapsedMs) / 1000 * Self.rateLimitTokensPerSecond
        )
        bucket.lastRefillMs = now

        let decision: RateLimitDecision
        if bucket.tokens >= 1 {
          bucket.tokens -= 1
          decision = .write(suppressed: bucket.suppressedCount)
          bucket.suppressedCount = 0
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

  private static let writer = ThreadSafe<Writer?>(nil)
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

    let writer = Container.shared.fileLogWriter((fileURL, maxFileSizeBytes, targetFileSizeBytes))
    Self.writer(writer)
    self.writer = writer
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

    writer.write(entry, synchronously: writeSynchronously(event.level))
  }

  // MARK: - Flush

  static func flush() {
    writer()?.flush()
  }
}
