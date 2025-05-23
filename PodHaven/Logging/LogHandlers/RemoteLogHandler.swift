// Copyright Justin Bishop, 2025

import Foundation
import Logging
@preconcurrency import ShipBookSDK
import System

extension Logger.Level {
  fileprivate var shipBookLogLevel: Severity {
    switch self {
    case .trace:
      return .Verbose
    case .debug:
      return .Debug
    case .info:
      return .Info
    case .notice:
      return .Warning
    case .warning:
      return .Warning
    case .error:
      return .Error
    case .critical:
      return .Error
    }
  }
}

struct RemoteLogHandler: LogHandler {
  public var metadata: Logger.Metadata = [:]
  public var metadataProvider: Logger.MetadataProvider?
  public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
    get { self.metadata[metadataKey] }
    set(newValue) { self.metadata[metadataKey] = newValue }
  }
  public var logLevel: Logger.Level = .debug

  private let log: ShipBookSDK.Log

  init(label: String) {
    self.log = ShipBook.getLogger(label)
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
    log.message(
      msg: message.description,
      severity: level.shipBookLogLevel,
      function: function,
      file: file,
      line: Int(line)
    )
  }
}
