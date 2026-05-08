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
  public var logLevel: Logger.Level = .trace

  private let label: String

  init(label: String) {
    self.label = label
  }

  public func log(event: LogEvent) {
    print("[\(event.level)] \(label): \(event.message)")
  }
}
