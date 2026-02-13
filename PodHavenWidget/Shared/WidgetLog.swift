// Copyright Justin Bishop, 2026

import Foundation
import OSLog

// Lightweight logger for the widget extension that writes NDJSON entries
// to widget-log.ndjson in the app group container. Uses NDJSONLogEntry and
// NDJSONFileWriter shared with the main app for compatible output that the
// analyze-logs skill can parse. Also logs to OSLog for Xcode console
// visibility during development.
enum WidgetLog {
  private static let osLog = Logger(subsystem: "PodHavenWidget", category: "Widget")

  private static let logQueue = DispatchQueue(label: "WidgetLog", qos: .utility)

  private static let maxFileSizeBytes = 500_000  // 500KB trigger
  private static let targetFileSizeBytes = 400_000  // 400KB after truncation

  static func debug(
    _ message: String,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
  ) {
    log(level: "debug", levelInt: 1, message: message, file: file, function: function, line: line)
    osLog.debug("\(message, privacy: .public)")
  }

  static func info(
    _ message: String,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
  ) {
    log(level: "info", levelInt: 2, message: message, file: file, function: function, line: line)
    osLog.info("\(message, privacy: .public)")
  }

  static func warning(
    _ message: String,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
  ) {
    log(level: "warning", levelInt: 4, message: message, file: file, function: function, line: line)
    osLog.warning("\(message, privacy: .public)")
  }

  static func error(
    _ message: String,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
  ) {
    log(level: "error", levelInt: 5, message: message, file: file, function: function, line: line)
    osLog.error("\(message, privacy: .public)")
  }

  // MARK: - Private

  private static func log(
    level: String,
    levelInt: Int,
    message: String,
    file: String,
    function: String,
    line: UInt
  ) {
    let entry = NDJSONLogEntry(
      level: levelInt,
      levelName: level,
      timestamp: Int64(Date().timeIntervalSince1970 * 1000),
      subsystem: "PodHavenWidget",
      category: "Widget",
      message: message,
      metadata: nil,
      source: "PodHavenWidget",
      file: file,
      function: function,
      line: line
    )

    logQueue.async {
      do {
        let currentSize = try NDJSONFileWriter.appendEntry(
          entry,
          to: WidgetConstants.widgetLogFileURL
        )
        if currentSize > UInt64(maxFileSizeBytes) {
          try NDJSONFileWriter.truncateIfNeeded(
            at: WidgetConstants.widgetLogFileURL,
            maxSize: maxFileSizeBytes,
            targetSize: targetFileSizeBytes
          )
        }
      } catch {
        osLog.error("Failed to write log entry: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
}
