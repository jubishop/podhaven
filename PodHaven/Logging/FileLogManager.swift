// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import Sentry

extension Container {
  var fileLogManager: Factory<FileLogManager> {
    Factory(self) { FileLogManager() }.scope(.cached)
  }
}

struct FileLogManager: Sendable {
  @DynamicInjected(\.sleeper) private var sleeper

  private let maxLogEntries = 2500
  private let periodicCleanupInterval = Duration.minutes(15)

  private let logQueue = DispatchQueue(label: "FileLogHandler", qos: .background)
  private let logFileURL: URL = {
    return AppInfo.documentsDirectory.appendingPathComponent("log.ndjson")
  }()

  private static let log = Log.as("FileLogCleaner", level: .debug)

  // MARK: - Initialization

  fileprivate init() {
    startPeriodicCleanup()
  }

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
      guard let jsonString = String(data: try JSONEncoder().encode(fileLogEntry), encoding: .utf8)
      else { throw LoggingError.jsonStringCreationFailure(fileLogEntry) }

      if FileManager.default.fileExists(atPath: logFileURL.path) {
        let fileHandle = try FileHandle(forWritingTo: logFileURL)
        fileHandle.seekToEndOfFile()
        fileHandle.write("\(jsonString)\n".data(using: .utf8)!)
        fileHandle.closeFile()
      } else {
        try jsonString.write(to: logFileURL, atomically: true, encoding: .utf8)
      }
    } catch {
      Self.log.error(error)
    }
  }

  // MARK: - Cleanup

  private func startPeriodicCleanup() {
    Assert.neverCalled()

    Task(priority: .background) {
      while true {
        do {
          Self.log.debug("Running periodic log truncation after \(periodicCleanupInterval)")
          await truncateLogFile()

          try await sleeper.sleep(for: periodicCleanupInterval)
        } catch {
          Self.log.error(error)
        }
      }
    }
  }

  private func truncateLogFile() async {
    guard FileManager.default.fileExists(atPath: logFileURL.path)
    else {
      Self.log.error("Log file does not exist?")
      return
    }

    await withCheckedContinuation { continuation in
      logQueue.async {
        do {
          let logContent = try String(contentsOf: logFileURL, encoding: .utf8)
          let lines = logContent.components(separatedBy: .newlines).filter { !$0.isEmpty }

          guard lines.count > maxLogEntries
          else {
            Self.log.debug("Log file has \(lines.count) entries, no truncation needed")
            return
          }

          let keepLines = Array(lines.suffix(maxLogEntries))
          let truncatedContent = keepLines.joined(separator: "\n")
          try (truncatedContent + "\n").write(to: logFileURL, atomically: true, encoding: .utf8)
          Self.log.info("Truncated log file from \(lines.count) to \(keepLines.count) entries")
        } catch {
          Self.log.error(error)
        }

        continuation.resume()
      }
    }
  }
}
