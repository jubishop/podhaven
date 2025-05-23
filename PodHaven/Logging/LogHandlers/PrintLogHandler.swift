// Copyright Justin Bishop, 2025

import Foundation
import Logging

struct PrintLogHandler: LogHandler {
  public var metadata: Logger.Metadata = [:]
  public var metadataProvider: Logger.MetadataProvider?
  public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
    get { self.metadata[metadataKey] }
    set(newValue) { self.metadata[metadataKey] = newValue }
  }
  public var logLevel: Logger.Level = .debug

  private let category: String
  private let subsystem: String

  init(label: String) {
    (category, subsystem) = LogKit.destructureLabel(from: label)
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
    print("[\(level)] \(LogKit.label(category: category, subsystem: subsystem)): \(message)")
  }
}
