// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import SwiftUI

extension Container {
  var fileLogManager: Factory<FileLogManager> {
    Factory(self) { FileLogManager() }.scope(.cached)
  }
}

struct FileLogManager: Sendable {
  private let maxFileSizeBytes: UInt64 = 2_000_000  // 2MB trigger
  private let targetFileSizeBytes: UInt64 = 1_750_000  // 1.75MB after truncation

  private let logQueue = DispatchQueue(label: "FileLogHandler", qos: .background)
  private let isActive = ThreadSafe(true)
  private let logFileURL: URL = {
    AppInfo.documentsDirectory.appendingPathComponent("log.ndjson")
  }()

  private static let log = Log.as("FileLogManager")

  // MARK: - Initialization

  fileprivate init() {}

  // MARK: - Logging

  func writeToFile(level: Logger.Level, fileLogEntry: FileLogEntry) {
    let runSynchronously = level == .critical || !isActive()

    if runSynchronously {
      let result = logQueue.sync { performWriteToFile(fileLogEntry) }
      Self.log.logResult(result)
    } else {
      logQueue.async {
        let result = performWriteToFile(fileLogEntry)
        Task(priority: .background) {
          Self.log.logResult(result)
        }
      }
    }
  }

  // MARK: - Scene Phase

  func handleScenePhaseChange(to scenePhase: ScenePhase) {
    switch scenePhase {
    case .active:
      isActive(true)
    case .background:
      isActive(false)
      logQueue.sync {}
    default:
      break
    }
  }

  // MARK: - File Operations

  private func performWriteToFile(_ fileLogEntry: FileLogEntry) -> LogResult {
    do {
      let jsonData = try JSONEncoder().encode(fileLogEntry)
      guard let newlineData = "\n".data(using: .utf8)
      else { throw LoggingError.dataEncodingFailure("\n") }

      var writeData = jsonData
      writeData.append(newlineData)

      var followUp: LogResult?

      do {
        let fileHandle = try FileHandle(forWritingTo: logFileURL)
        defer { fileHandle.closeFile() }

        fileHandle.seekToEndOfFile()
        fileHandle.write(writeData)

        let currentSize = fileHandle.offsetInFile
        if currentSize > maxFileSizeBytes {
          followUp = try truncateLogFile()
        }
      } catch CocoaError.fileNoSuchFile {
        // File doesn't exist, create it
        try writeData.write(to: logFileURL)
      }

      guard let followUp else { return .success }
      return followUp
    } catch {
      return .failure(error)
    }
  }

  // MARK: - Cleanup

  private func truncateLogFile() throws -> LogResult {
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

    return .log(
      .info,
      "File log truncated from \(fileData.count) bytes to \(truncatedData.count) bytes"
    )
  }
}
