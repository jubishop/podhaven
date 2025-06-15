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
  @Shared(.appStorage("FileLogManager.lastCleanup")) private var lastCleanup: Double = 0
  private let logRetentionInterval = 12.hours
  private let periodicCleanupInterval = 1.hours

  private let logQueue = DispatchQueue(label: "FileLogHandler", qos: .background)
  private let logFileURL: URL = {
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    return documentsURL.appendingPathComponent("log.ndjson")
  }()

  private let log = Log.as("FileLogCleaner")

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

    let notifications = Container.shared.notifications()

    Task {
      log.debug("App launched, checking if log cleanup needed")
      await cleanupIfNeeded()
    }

    Task {
      for await _ in notifications(UIApplication.didBecomeActiveNotification) {
        log.debug("App became active, checking if log cleanup needed")
        await cleanupIfNeeded()
      }
    }

    Task {
      for await _ in notifications(UIApplication.didEnterBackgroundNotification) {
        log.debug("App backgrounded, checking if log cleanup needed")
        await cleanupIfNeeded()
      }
    }
  }

  private func cleanupIfNeeded() async {
    let now = Date().timeIntervalSince1970

    if now - lastCleanup > periodicCleanupInterval {
      log.debug("Running periodic log cleanup")
      $lastCleanup.withLock { $0 = now }
      let backgroundTaskID = await UIApplication.shared.beginBackgroundTask {}
      await withCheckedContinuation { continuation in
        logQueue.async {
          cleanupOldLogs()
          continuation.resume()
        }
      }
      if backgroundTaskID != .invalid {
        await UIApplication.shared.endBackgroundTask(backgroundTaskID)
      }
    }
  }

  private func cleanupOldLogs() {
    guard FileManager.default.fileExists(atPath: logFileURL.path) else { return }

    do {
      let cutoffDate = Date().addingTimeInterval(-logRetentionInterval)
      let cutoffTimestamp = Int64(cutoffDate.timeIntervalSince1970 * 1000)

      let logContent = try String(contentsOf: logFileURL, encoding: .utf8)
      let lines = logContent.components(separatedBy: .newlines)
      let filteredLines = lines.compactMap { line -> String? in
        guard !line.isEmpty else { return nil }

        do {
          if let data = line.data(using: .utf8),
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let timestamp = json["timestamp"] as? Int64,
            timestamp >= cutoffTimestamp
          {
            return line
          }
          return nil
        } catch {
          SentrySDK.capture(error: error)
          return nil
        }
      }

      let filteredContent = filteredLines.joined(separator: "\n")
      if !filteredContent.isEmpty {
        try (filteredContent + "\n").write(to: logFileURL, atomically: true, encoding: .utf8)
      } else {
        try "".write(to: logFileURL, atomically: true, encoding: .utf8)
      }
    } catch {
      SentrySDK.capture(error: error)
    }
  }
}
