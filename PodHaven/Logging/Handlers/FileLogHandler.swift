// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

struct FileLogHandler: LogHandler {
  private struct LogEntry: Codable {
    let level: String
    let message: String
    let metadata: [String: String]?
    let source: String
    let file: String
    let function: String
    let line: UInt
    let timestamp: Int64
    let threadID: String
    let isMainThread: Bool
    let containerID: String
    let subsystem: String
    let category: String
  }

  @DynamicInjected(\.containerID) private var containerID

  public var metadata: Logging.Logger.Metadata = [:]
  public var metadataProvider: Logging.Logger.MetadataProvider?
  public subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
    get { self.metadata[metadataKey] }
    set(newValue) { self.metadata[metadataKey] = newValue }
  }
  public var logLevel: Logging.Logger.Level = .trace

  private let logQueue = DispatchQueue(label: "FileLogHandler", qos: .background)
  private let logFileURL: URL
  private let subsystem: String
  private let category: String

  init(label: String) {
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    self.logFileURL = documentsURL.appendingPathComponent("log.ndjson")

    let (subsystem, category) = LogKit.destructureLabel(from: label)
    self.subsystem = subsystem
    self.category = category

    cleanupOldLogs()
  }

  public func log(
    level: Logging.Logger.Level,
    message: Logging.Logger.Message,
    metadata: Logging.Logger.Metadata?,
    source: String,
    file: String,
    function: String,
    line: UInt
  ) {
    let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
    let threadID = Thread.id
    let isMainThread = Thread.isMainThread
    let containerIDValue = containerID

    let mergedMetadata = LogKit.merge(
      handler: self.metadata,
      provider: self.metadataProvider,
      oneOff: metadata
    )

    let logEntry = LogEntry(
      level: level.rawValue,
      message: message.description,
      metadata: mergedMetadata.isEmpty
        ? nil
        : Dictionary(uniqueKeysWithValues: mergedMetadata.map { ($0.key, $0.value.description) }),
      source: source,
      file: file,
      function: function,
      line: line,
      timestamp: timestamp,
      threadID: threadID,
      isMainThread: isMainThread,
      containerID: containerIDValue,
      subsystem: subsystem,
      category: category
    )

    if level == .critical {
      logQueue.sync {
        writeLogEntry(logEntry)
      }
    } else {
      logQueue.async {
        writeLogEntry(logEntry)
      }
    }
  }

  private func writeLogEntry(_ logEntry: LogEntry) {
    do {
      let jsonData = try JSONEncoder().encode(logEntry)
      let jsonString = String(data: jsonData, encoding: .utf8)! + "\n"

      if FileManager.default.fileExists(atPath: logFileURL.path) {
        let fileHandle = try FileHandle(forWritingTo: logFileURL)
        fileHandle.seekToEndOfFile()
        fileHandle.write(jsonString.data(using: .utf8)!)
        fileHandle.closeFile()
      } else {
        try jsonString.write(to: logFileURL, atomically: true, encoding: .utf8)
      }
    } catch {
      // Failed to write log - we can't use the logger here to avoid recursion
      print("FileLogHandler failed to write log: \(error)")
    }
  }

  private func cleanupOldLogs() {
    logQueue.async {
      guard FileManager.default.fileExists(atPath: logFileURL.path) else { return }

      do {
        let threeDaysAgo = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        let threeDaysAgoTimestamp = Int64(threeDaysAgo.timeIntervalSince1970 * 1000)

        let logContent = try String(contentsOf: logFileURL, encoding: .utf8)
        let lines = logContent.components(separatedBy: .newlines)

        let filteredLines = lines.compactMap { line -> String? in
          guard !line.isEmpty else { return nil }

          do {
            if let data = line.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timestamp = json["timestamp"] as? Int64,
              timestamp >= threeDaysAgoTimestamp
            {
              return line
            }
            return nil
          } catch {
            return line
          }
        }

        let filteredContent = filteredLines.joined(separator: "\n")
        if !filteredContent.isEmpty {
          try (filteredContent + "\n").write(to: logFileURL, atomically: true, encoding: .utf8)
        } else {
          try "".write(to: logFileURL, atomically: true, encoding: .utf8)
        }
      } catch {
        print("FileLogHandler failed to cleanup old logs: \(error)")
      }
    }
  }
}
