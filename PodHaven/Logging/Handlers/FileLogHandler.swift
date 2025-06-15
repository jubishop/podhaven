// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import Sentry
import UIKit

struct FileLogEntry: Codable {
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

struct FileLogHandler: LogHandler {
  private static let logRetentionInterval = 12.hours
  private static let logQueue = DispatchQueue(label: "FileLogHandler", qos: .background)
  private static let logFileURL: URL = {
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    return documentsURL.appendingPathComponent("log.ndjson")
  }()

  public var metadata: Logger.Metadata = [:]
  public var metadataProvider: Logger.MetadataProvider?
  public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
    get { self.metadata[metadataKey] }
    set(newValue) { self.metadata[metadataKey] = newValue }
  }
  public var logLevel: Logger.Level = .trace

  private let subsystem: String
  private let category: String

  init(label: String) {
    let (subsystem, category) = LogKit.destructureLabel(from: label)
    self.subsystem = subsystem
    self.category = category
  }

  public func log(
    level: Logger.Level,
    message: Logger.Message,
    metadata: Logger.Metadata?,
    source: String,
    file: String,
    function: String,
    line: UInt
  ) {
    let mergedMetadata = LogKit.merge(
      handler: self.metadata,
      provider: self.metadataProvider,
      oneOff: metadata
    )

    let logEntry = FileLogEntry(
      level: level.intValue,
      levelName: level.rawValue,
      timestamp: Int64(Date().timeIntervalSince1970 * 1000),
      subsystem: subsystem,
      category: category,
      message: message.description,
      metadata: mergedMetadata.isEmpty
        ? nil
        : Dictionary(uniqueKeysWithValues: mergedMetadata.map { ($0.key, $0.value.description) }),
      source: source,
      file: file,
      function: function,
      line: line,
    )

    if level == .critical {
      Self.logQueue.sync(flags: .barrier) {
        Self.writeToFile(logEntry)
      }
    } else {
      Self.logQueue.async {
        Self.writeToFile(logEntry)
      }
    }
  }

  private static func writeToFile(_ logEntry: FileLogEntry) {
    do {
      guard let jsonString = String(data: try JSONEncoder().encode(logEntry), encoding: .utf8)
      else { throw LoggingError.jsonStringCreationFailure(logEntry) }

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

  // MARK: - Rotating Logs

  static func startBackgroundCleanup() {
    Assert.neverCalled()

    let log = Log.as("FileLogCleaner")
    let notifications = Container.shared.notifications()
    Task { @MainActor in
      for await _ in notifications(UIApplication.didEnterBackgroundNotification) {
        let backgroundTaskID = UIApplication.shared.beginBackgroundTask {}

        log.debug("Now cleaning logs in background")
        cleanupOldLogs()

        if backgroundTaskID != .invalid {
          UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }
      }
    }
  }

  private static func cleanupOldLogs() {
    logQueue.async {
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
}
