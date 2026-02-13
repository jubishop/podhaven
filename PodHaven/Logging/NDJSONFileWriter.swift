// Copyright Justin Bishop, 2026

import Foundation

// Shared NDJSON file writer used by both the main app (FileLogManager) and the
// widget extension (WidgetLog). Foundation-only so it compiles in either target
// without pulling in Logging, FactoryKit, or other app-specific dependencies.
enum NDJSONFileWriter {

  // MARK: - Writing

  // Encodes the entry as JSON, appends it with a trailing newline to the file
  // at `url`, and returns the file size after the write. Creates the file if
  // it doesn't already exist.
  @discardableResult
  static func appendEntry(_ entry: NDJSONLogEntry, to url: URL) throws -> UInt64 {
    var data = try JSONEncoder().encode(entry)
    data.append(0x0A)  // newline

    do {
      let handle = try FileHandle(forWritingTo: url)
      defer { handle.closeFile() }
      handle.seekToEndOfFile()
      handle.write(data)
      return handle.offsetInFile
    } catch CocoaError.fileNoSuchFile {
      try data.write(to: url)
      return UInt64(data.count)
    }
  }

  // MARK: - Truncation

  // Removes the oldest NDJSON lines from the file until its size is at or
  // below `targetSize`. Only acts when the file exceeds `maxSize`.
  // Returns the original and new byte counts when truncation occurs,
  // or nil if no truncation was needed.
  @discardableResult
  static func truncateIfNeeded(
    at url: URL,
    maxSize: Int,
    targetSize: Int
  ) throws -> (originalSize: Int, newSize: Int)? {
    let data = try Data(contentsOf: url)
    guard data.count > maxSize else { return nil }

    let bytesToRemove = data.count - targetSize
    guard bytesToRemove > 0 else { return nil }

    let searchRange = bytesToRemove..<data.count
    guard let newlineIndex = data[searchRange].firstIndex(of: 0x0A) else { return nil }

    let truncated = data[(newlineIndex + 1)...]
    try truncated.write(to: url, options: .atomic)

    return (originalSize: data.count, newSize: truncated.count)
  }
}
