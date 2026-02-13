// Copyright Justin Bishop, 2026

import Foundation

// A single NDJSON log entry shared by the main app and widget extension.
// Both targets produce compatible output that the analyze-logs skill can parse.
struct NDJSONLogEntry: Codable {
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
