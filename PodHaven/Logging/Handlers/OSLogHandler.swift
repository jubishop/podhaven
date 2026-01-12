// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import os

extension Logging.Logger.Level {
  fileprivate var osLogLevel: OSLogType {
    switch self {
    case .trace:
      return .debug
    case .debug:
      return .debug
    case .info:
      return .info
    case .notice:
      return .info
    case .warning:
      return .error
    case .error:
      return .error
    case .critical:
      return .fault
    }
  }
}

struct OSLogHandler: LogHandler {
  public var metadata: Logging.Logger.Metadata = [:]
  public var metadataProvider: Logging.Logger.MetadataProvider?
  public subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
    get { self.metadata[metadataKey] }
    set(newValue) { self.metadata[metadataKey] = newValue }
  }
  public var logLevel: Logging.Logger.Level = .trace

  private let logger: os.Logger

  init(label: String) {
    let (subsystem, category) = LogKit.destructureLabel(from: label)
    logger = os.Logger(subsystem: subsystem, category: category)
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
    #if DEBUG
    let system = Log.getTestSystem()
    if !system.isEmpty {
      logger.log(
        level: level.osLogLevel,
        """
        \(system):
        \(message, privacy: .public)
        """
      )
      return
    }
    #endif

    logger.log(level: level.osLogLevel, "\(message, privacy: .public)")
  }
}
