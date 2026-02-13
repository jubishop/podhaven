// Copyright Justin Bishop, 2026

import Foundation
import OSLog

// Lightweight logger for the widget extension that writes NDJSON entries
// to widget-log.ndjson in the app group container. Uses the same NDJSON
// format as the main app for compatibility with analyze-logs. Also logs
// to OSLog for Xcode console visibility during development.
enum WidgetLog {
  private static let osLog = Logger(subsystem: "PodHavenWidget", category: "Widget")

  private static let logQueue = DispatchQueue(label: "WidgetLog", qos: .utility)

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
    let entry = WidgetLogEntry(
      level: levelInt,
      levelName: level,
      timestamp: Int64(Date().timeIntervalSince1970 * 1000),
      subsystem: "Widget",
      category: "widget",
      message: message,
      source: "PodHavenWidget",
      file: file,
      function: function,
      line: line
    )

    logQueue.async {
      writeEntry(entry)
    }
  }

  private static func writeEntry(_ entry: WidgetLogEntry) {
    do {
      var data = try JSONEncoder().encode(entry)
      guard let newline = "\n".data(using: .utf8) else { return }
      data.append(newline)

      let url = WidgetConstants.widgetLogFileURL

      do {
        let fileHandle = try FileHandle(forWritingTo: url)
        defer { fileHandle.closeFile() }
        fileHandle.seekToEndOfFile()
        fileHandle.write(data)
      } catch CocoaError.fileNoSuchFile {
        try data.write(to: url)
      }
    } catch {
      osLog.error("Failed to write log entry: \(error.localizedDescription, privacy: .public)")
    }
  }
}

// Same shape as the main app's FileLogEntry so both produce
// compatible NDJSON that the analyze-logs skill can parse.
private struct WidgetLogEntry: Codable {
  let level: Int
  let levelName: String
  let timestamp: Int64
  let subsystem: String
  let category: String
  let message: String
  let source: String
  let file: String
  let function: String
  let line: UInt
}
