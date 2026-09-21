// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import Sentry
import Synchronization

protocol SentryLogEmitting {
  func trace(_ body: String, attributes: [String: Any])
  func debug(_ body: String, attributes: [String: Any])
  func info(_ body: String, attributes: [String: Any])
  func warn(_ body: String, attributes: [String: Any])
  func error(_ body: String, attributes: [String: Any])
  func fatal(_ body: String, attributes: [String: Any])
}

extension SentryLogger: SentryLogEmitting {}

extension Container {
  var sentryLogger: Factory<any SentryLogEmitting> {
    Factory(self) { SentrySDK.logger }.scope(.cached)
  }
}

struct SentryLogHandler: LogHandler {
  public var metadata: Logging.Logger.Metadata = [:]
  public var metadataProvider: Logging.Logger.MetadataProvider?
  public subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
    get { self.metadata[metadataKey] }
    set(newValue) { self.metadata[metadataKey] = newValue }
  }
  public var logLevel: Logger.Level {
    get { .warning }
    set {}  // Ignore
  }

  private let subsystem: String
  private let category: String

  init(label: String) {
    (self.subsystem, self.category) = LogKit.destructureLabel(from: label)
  }

  public func log(event: LogEvent) {
    let logger = Container.shared.sentryLogger()
    let message = String(describing: event.message)
    var attributes =
      [
        "severity": event.level,
        "subsystem": subsystem,
        "category": category,
        "version": AppInfo.version,
        "buildNumber": AppInfo.buildNumber,
        "buildDate": AppInfo.buildDate,
        "gitCommitHash": AppInfo.gitCommitHash,
        "logSessionID": FileLogHandler.sessionID,
      ] as [String: Any]

    let metadata = LogKit.merge(
      handler: self.metadata,
      provider: metadataProvider,
      oneOff: event.metadata
    )
    if category == "MetricKit", metadata["metricKit.kind"] == "aggregate_exits" {
      for key in [
        "metricKit.kind", "metricKit.scope", "metricKit.periodStart", "metricKit.periodEnd",
        "metricKit.latestVersion", "metricKit.payloadBuild", "metricKit.multipleVersions",
        "metricKit.attribution",
      ] {
        if let value = metadata[key] { attributes[key] = String(value.description.prefix(64)) }
      }
      for key in [
        "normalAppExit", "memoryResourceLimit", "cpuResourceLimit", "memoryPressure",
        "badAccess", "abnormal", "illegalInstruction", "appWatchdog", "suspendedWithLockedFile",
        "backgroundTaskAssertionTimeout",
      ] {
        if let value = metadata[key] {
          attributes["metricKit.\(key)"] = String(value.description.prefix(32))
        }
      }
    }

    switch event.level {
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
