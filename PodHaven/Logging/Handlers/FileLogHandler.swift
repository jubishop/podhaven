// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

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
  @DynamicInjected(\.fileLogManager) private var fileLogManager

  // MARK: - LogHandler

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

    fileLogManager.writeToFile(
      level: level,
      fileLogEntry: FileLogEntry(
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
    )
  }
}
