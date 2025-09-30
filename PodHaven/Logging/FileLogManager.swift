// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

extension Container {
  var fileLogManager: Factory<FileLogManager> {
    Factory(self) { FileLogManager() }.scope(.cached)
  }
}

struct FileLogManager: Sendable {
  private let maxFileSizeBytes: UInt64 = 1_000_000  // 1MB trigger
  private let targetFileSizeBytes: UInt64 = 750_000  // 750KB after truncation

  private let logQueue = DispatchQueue(label: "FileLogHandler", qos: .background)
  private let logFileURL: URL = {
    AppInfo.documentsDirectory.appendingPathComponent("log.ndjson")
  }()

  private static let log = Log.as("FileLogManager", level: .debug)

  // MARK: - Initialization

  fileprivate init() {}

  // MARK: - Logging

  func writeToFile(level: Logger.Level, fileLogEntry: FileLogEntry) {
    if level == .critical {
      logQueue.sync(flags: .barrier) {
        performWriteToFile(fileLogEntry)
      }
    } else {
      logQueue.async {
        performWriteToFile(fileLogEntry)
      }
    }
  }

  private func performWriteToFile(_ fileLogEntry: FileLogEntry) {
    do {
      let jsonData = try JSONEncoder().encode(fileLogEntry)
      guard let newlineData = "\n".data(using: .utf8)
      else { throw LoggingError.dataEncodingFailure("\n") }

      var writeData = jsonData
      writeData.append(newlineData)

      do {
        let fileHandle = try FileHandle(forWritingTo: logFileURL)
        defer { fileHandle.closeFile() }

        fileHandle.seekToEndOfFile()
        fileHandle.write(writeData)

        let currentSize = fileHandle.offsetInFile
        if currentSize > maxFileSizeBytes {
          try truncateLogFile()
        }
      } catch CocoaError.fileNoSuchFile {
        // File doesn't exist, create it
        try writeData.write(to: logFileURL)
      }
    } catch {
      Self.log.error(error)
    }
  }

  // MARK: - Cleanup

  private func truncateLogFile() throws {
    let fileData = try Data(contentsOf: logFileURL)

    let bytesToRemove = fileData.count - Int(targetFileSizeBytes)
    guard bytesToRemove > 0
    else { throw LoggingError.truncationNegativeBytes(bytesToRemove) }

    // Find the first newline after the cutoff to keep valid JSON lines
    let searchRange = bytesToRemove..<fileData.count
    guard let newlineIndex = fileData[searchRange].firstIndex(of: UInt8(ascii: "\n"))
    else { throw LoggingError.truncationNoNewlineFound(bytesToRemove) }

    // Keep everything after the newline
    let truncatedData = fileData[(newlineIndex + 1)...]
    try truncatedData.write(to: logFileURL, options: .atomic)
    Self.log.info("Truncated log file from \(fileData.count) bytes to \(truncatedData.count) bytes")
  }
}
