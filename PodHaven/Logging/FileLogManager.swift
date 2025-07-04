// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import Sentry
import Sharing
import UIKit

extension Container {
  var fileLogManager: Factory<FileLogManager> {
    Factory(self) { FileLogManager() }.scope(.cached)
  }
}

struct FileLogManager: Sendable {
  @DynamicInjected(\.notifications) private var notifications

  @Shared(.appStorage("FileLogManager-lastCleanup")) private var lastCleanup: Double = 0
  private let maxLogEntries = 5000
  private let periodicCleanupInterval = 1.hours

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
      SentrySDK.capture(error: error)
    }
  }

  // MARK: - Cleanup

  func startPeriodicCleanup() {
    Assert.neverCalled()

    Task(priority: .background) {
      if await UIApplication.shared.applicationState == .active {
        Self.log.trace("App launched, checking if log truncation needed")
        await truncateIfNeeded()
      }
    }

    Task(priority: .background) {
      for await _ in notifications(UIApplication.didBecomeActiveNotification) {
        Self.log.trace("App became active, checking if log truncation needed")
        await truncateIfNeeded()
      }
    }

    Task(priority: .background) {
      for await _ in notifications(UIApplication.willResignActiveNotification) {
        Self.log.trace("App will resign active, checking if log truncation needed")
        await truncateIfNeeded()
      }
    }
  }

  private func truncateIfNeeded() async {
    let now = Date().timeIntervalSince1970
    let timeSinceLastCleanup = now - lastCleanup

    if timeSinceLastCleanup > periodicCleanupInterval {
      Self.log.debug(
        """
        Running periodic log truncation, \
        last cleanup was: \(timeSinceLastCleanup.compactReadableFormat) ago
        """
      )
      $lastCleanup.withLock { $0 = now }

      let backgroundTaskID = await UIApplication.shared.beginBackgroundTask()

      await withCheckedContinuation { continuation in
        logQueue.async {
          truncateLogFile()
          continuation.resume()
        }
      }

      if backgroundTaskID != .invalid {
        await UIApplication.shared.endBackgroundTask(backgroundTaskID)
      }
    }
  }

  private func truncateLogFile() {
    guard FileManager.default.fileExists(atPath: logFileURL.path) else { return }

    do {
      let logContent = try String(contentsOf: logFileURL, encoding: .utf8)
      let lines = logContent.components(separatedBy: .newlines).filter { !$0.isEmpty }

      guard lines.count > maxLogEntries else { return }

      let keepLines = Array(lines.suffix(maxLogEntries))
      let truncatedContent = keepLines.joined(separator: "\n")
      try (truncatedContent + "\n").write(to: logFileURL, atomically: true, encoding: .utf8)

      Self.log.info("Truncated log file from \(lines.count) to \(keepLines.count) entries")
    } catch {
      SentrySDK.capture(error: error)
    }
  }
}
