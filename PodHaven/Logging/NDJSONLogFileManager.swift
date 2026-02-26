// Copyright Justin Bishop, 2026

import Foundation
import Logging

// Shared NDJSON log file writer used by both the main app and the widget
// extension. Logs errors and truncation events via a static Logger.
struct NDJSONLogFileManager: Sendable {

  // MARK: - Configuration

  let fileURL: URL
  let maxFileSizeBytes: Int
  let targetFileSizeBytes: Int

  // MARK: - State

  private static let log = Log.as("FileLogWriter")
  private let queue: DispatchQueue

  // MARK: - Initialization

  init(
    fileURL: URL,
    maxFileSizeBytes: Int,
    targetFileSizeBytes: Int
  ) {
    self.fileURL = fileURL
    self.maxFileSizeBytes = maxFileSizeBytes
    self.targetFileSizeBytes = targetFileSizeBytes
    self.queue = DispatchQueue(label: "NDJSONLogFileManager", qos: .background)
  }

  // MARK: - Writing

  // Dispatches the write + truncate on the internal queue.
  func writeAsync(_ entry: NDJSONLogEntry) {
    queue.async {
      self.writeAndReport(entry)
    }
  }

  // Synchronous write on the internal queue.
  func writeSync(_ entry: NDJSONLogEntry) {
    queue.sync {
      self.writeAndReport(entry)
    }
  }

  // Drains the internal queue, ensuring all pending writes complete.
  func flush() {
    queue.sync {}
  }

  // MARK: - Private

  private func writeAndReport(_ entry: NDJSONLogEntry) {
    do {
      if let truncation = try write(entry) {
        Self.log.info(
          "Log truncated from \(truncation.originalSize) to \(truncation.newSize) bytes"
        )
      }
    } catch {
      Self.log.error(error)
    }
  }

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
