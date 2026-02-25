// Copyright Justin Bishop, 2025

import Foundation
import Logging

struct FileLogHandler: LogHandler {

  // MARK: - LogHandler

  public var metadata: Logger.Metadata = [:]
  public var metadataProvider: Logger.MetadataProvider?
  public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
    get { self.metadata[metadataKey] }
    set(newValue) { self.metadata[metadataKey] = newValue }
  }
  public var logLevel: Logger.Level = .trace

  // MARK: - State

  private let subsystem: String
  private let category: String
  private let writeEntry: @Sendable (Logger.Level, NDJSONLogEntry) -> Void

  // MARK: - Initialization

  init(label: String, writeEntry: @escaping @Sendable (Logger.Level, NDJSONLogEntry) -> Void) {
    let (subsystem, category) = LogKit.destructureLabel(from: label)
    self.subsystem = subsystem
    self.category = category
    self.writeEntry = writeEntry
  }

  // MARK: - Logging

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

    let entry = NDJSONLogEntry(
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
      line: line
    )

    writeEntry(level, entry)
  }
}
