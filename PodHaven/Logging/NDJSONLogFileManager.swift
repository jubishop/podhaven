// Copyright Justin Bishop, 2026

import Foundation

// Shared NDJSON log file writer used by both the main app (FileLogManager) and
// the widget extension. Foundation-only so it compiles in either target without
// pulling in Logging, FactoryKit, or other app-specific dependencies.
// Parameterized with file URL, size limits, and callbacks so each target can
// handle errors and truncation events with its own logging system.
struct NDJSONLogFileManager: Sendable {

  // MARK: - Configuration

  let fileURL: URL
  let maxFileSizeBytes: Int
  let targetFileSizeBytes: Int

  let onError: @Sendable (any Error) -> Void
  let onTruncation: @Sendable (_ originalSize: Int, _ newSize: Int) -> Void

  // MARK: - State

  private let queue: DispatchQueue

  // MARK: - Initialization

  init(
    fileURL: URL,
    maxFileSizeBytes: Int,
    targetFileSizeBytes: Int,
    queueLabel: String,
    onError: @escaping @Sendable (any Error) -> Void,
    onTruncation: @escaping @Sendable (_ originalSize: Int, _ newSize: Int) -> Void
  ) {
    self.fileURL = fileURL
    self.maxFileSizeBytes = maxFileSizeBytes
    self.targetFileSizeBytes = targetFileSizeBytes
    self.onError = onError
    self.onTruncation = onTruncation
    self.queue = DispatchQueue(label: queueLabel, qos: .background)
  }

  // MARK: - Writing

  // Dispatches the write + truncate on the internal queue. Calls onError or
  // onTruncation callbacks as appropriate.
  func writeAsync(_ entry: NDJSONLogEntry) {
    queue.async {
      do {
        let truncation = try self.write(entry)
        if let truncation {
          self.onTruncation(truncation.originalSize, truncation.newSize)
        }
      } catch {
        self.onError(error)
      }
    }
  }

  // Synchronous write on the internal queue. Returns truncation info if
  // truncation occurred, nil otherwise. Throws on write failure.
  func writeSync(_ entry: NDJSONLogEntry) throws -> (originalSize: Int, newSize: Int)? {
    try queue.sync {
      try self.write(entry)
    }
  }

  // Synchronous write on the internal queue. Reports errors and truncation
  // through the configured callbacks (like writeAsync does, but blocking).
  func writeSyncReporting(_ entry: NDJSONLogEntry) {
    queue.sync {
      do {
        if let truncation = try self.write(entry) {
          self.onTruncation(truncation.originalSize, truncation.newSize)
        }
      } catch {
        self.onError(error)
      }
    }
  }

  // Drains the internal queue, ensuring all pending writes complete.
  func flush() {
    queue.sync {}
  }

  // MARK: - Private

  private func write(_ entry: NDJSONLogEntry) throws -> (originalSize: Int, newSize: Int)? {
    let currentSize = try NDJSONFileWriter.appendEntry(entry, to: fileURL)

    if currentSize > UInt64(maxFileSizeBytes) {
      return try NDJSONFileWriter.truncateIfNeeded(
        at: fileURL,
        maxSize: maxFileSizeBytes,
        targetSize: targetFileSizeBytes
      )
    }

    return nil
  }
}
