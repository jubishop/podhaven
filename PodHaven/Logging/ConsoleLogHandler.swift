// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

public struct ConsoleLogHandler: LogHandler {
  public var metadata: Logger.Metadata = [:]
  public var metadataProvider: Logger.MetadataProvider?

  public init(label: String) {}

  public var logLevel: Logger.Level = .debug

  public func log(
    level: Logger.Level,
    message: Logger.Message,
    metadata: Logger.Metadata?,
    source: String,
    file: String,
    function: String,
    line: UInt
  ) {
    let currentMetadata = Log.merge(
      handler: self.metadata,
      provider: self.metadataProvider,
      oneOff: metadata
    )
    print(currentMetadata)
    print(message)
  }

  public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
    get {
      self.metadata[metadataKey]
    }
    set(newValue) {
      self.metadata[metadataKey] = newValue
    }
  }
}
