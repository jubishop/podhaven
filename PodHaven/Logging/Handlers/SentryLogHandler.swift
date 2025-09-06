// Copyright Justin Bishop, 2025

import Foundation
import Logging
import Sentry
import Synchronization

struct SentryLogHandler: LogHandler {
  public var metadata: Logging.Logger.Metadata = [:]
  public var metadataProvider: Logging.Logger.MetadataProvider?
  public subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
    get { self.metadata[metadataKey] }
    set(newValue) { self.metadata[metadataKey] = newValue }
  }
  public var logLevel: Logging.Logger.Level = .trace

  private let label: String

  init(label: String) {
    self.label = label
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
    let logger = SentrySDK.logger
    switch level {
    case .trace:
      logger.trace("\(label): \(message)")
    case .debug:
      logger.debug("\(label): \(message)")
    case .info, .notice:
      logger.info("\(label): \(message)")
    case .warning:
      logger.warn("\(label): \(message)")
    case .error:
      logger.error("\(label): \(message)")
    case .critical:
      logger.fatal("\(label): \(message)")
    }
  }
}
