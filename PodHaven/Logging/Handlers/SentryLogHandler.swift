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
  public var logLevel: Logger.Level {
    get { Logger.Level.notice }
    set {}  // Ignore
  }

  private let subsystem: String
  private let category: String

  init(label: String) {
    (self.subsystem, self.category) = LogKit.destructureLabel(from: label)
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
    let message = String(describing: message)
    let attributes =
      [
        "subsystem": subsystem,
        "category": category,
        "environment": AppInfo.environment,
        "deviceIdentifier": AppInfo.deviceIdentifier,
        "developerDevice": AppInfo.myDevice,
        "version": AppInfo.version,
        "buildNumber": AppInfo.buildNumber,
        "buildDate": AppInfo.buildDate,
      ] as [String: Any]

    switch level {
    case .trace:
      logger.trace(message, attributes: attributes)
    case .debug:
      logger.debug(message, attributes: attributes)
    case .info, .notice:
      logger.info(message, attributes: attributes)
    case .warning:
      logger.warn(message, attributes: attributes)
    case .error:
      logger.error(message, attributes: attributes)
    case .critical:
      logger.fatal(message, attributes: attributes)
    }
  }
}
