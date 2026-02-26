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
    let fileName = fileURL.deletingPathExtension().lastPathComponent
    self.queue = DispatchQueue(
      label: "com.artisanalsoftware.PodHaven.NDJSONLogFileManager.\(fileName)",
      qos: .background
    )
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
    let currentSize = try appendEntry(entry)

    if currentSize > UInt64(maxFileSizeBytes) {
      return try truncateIfNeeded()
    }

    return nil
  }

  // Encodes the entry as JSON, appends it with a trailing newline to the file
  // at `fileURL`, and returns the file size after the write. Creates the file
  // if it doesn't already exist.
  private func appendEntry(_ entry: NDJSONLogEntry) throws -> UInt64 {
    var data = try JSONEncoder().encode(entry)
    data.append(0x0A)  // newline

    do {
      let handle = try FileHandle(forWritingTo: fileURL)
      defer { handle.closeFile() }
      handle.seekToEndOfFile()
      handle.write(data)
      return handle.offsetInFile
    } catch CocoaError.fileNoSuchFile {
      try data.write(to: fileURL)
      return UInt64(data.count)
    }
  }

  // Removes the oldest NDJSON lines from the file until its size is at or
  // below `targetFileSizeBytes`. Only acts when the file exceeds
  // `maxFileSizeBytes`. Returns the original and new byte counts when
  // truncation occurs, or nil if no truncation was needed.
  private func truncateIfNeeded() throws -> (originalSize: Int, newSize: Int)? {
    let data = try Data(contentsOf: fileURL)
    guard data.count > maxFileSizeBytes else { return nil }

    let bytesToRemove = data.count - targetFileSizeBytes
    guard bytesToRemove > 0 else { return nil }

    let searchRange = bytesToRemove..<data.count
    guard let newlineIndex = data[searchRange].firstIndex(of: 0x0A) else { return nil }

    let truncated = data[(newlineIndex + 1)...]
    try truncated.write(to: fileURL, options: .atomic)

    return (originalSize: data.count, newSize: truncated.count)
  }
}
