// Copyright Justin Bishop, 2025

import BugfenderSDK
import Foundation
import Logging
import System

extension Logger.Level {
  fileprivate var bugFenderLogLevel: BFLogLevel {
    switch self {
    case .trace:
      return .trace
    case .debug:
      return .default
    case .info:
      return .info
    case .notice:
      return .info
    case .warning:
      return .warning
    case .error:
      return .error
    case .critical:
      return .fatal
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

  private var _logLevel: Logger.Level = .critical
  public var logLevel: Logger.Level {
    get {
      guard _logLevel >= .debug else { return .debug }
      return _logLevel
    }
    set { _logLevel = newValue }
  }

  private let label: String

  init(label: String) {
    self.label = label
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
    guard level > .trace else { return }

    Bugfender.log(
      lineNumber: Int(line),
      method: function,
      file: file,
      level: level.bugFenderLogLevel,
      tag: label,
      message: message.description
    )
  }
}
