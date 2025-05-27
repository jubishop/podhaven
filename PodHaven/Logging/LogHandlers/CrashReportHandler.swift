// Copyright Justin Bishop, 2025

import BugfenderSDK
import Foundation
import Honeybadger
import Logging
import Sentry
import System

struct CrashReportHandler: LogHandler {
  public var metadata: Logger.Metadata = [:]
  public var metadataProvider: Logger.MetadataProvider?
  public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
    get { self.metadata[metadataKey] }
    set(newValue) { self.metadata[metadataKey] = newValue }
  }
  public var logLevel: Logger.Level {
    get { .critical }
    set {}  // Ignore
  }

  private let category: String
  private let subsystem: String

  init(label: String) {
    (subsystem, category) = LogKit.destructureLabel(from: label)
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
    let filePath = FilePath(file)

    SentrySDK.capture(message: message.description)
    Honeybadger.notify(
      errorString: message.description,
      context: ["subsystem": subsystem, "category": category]
    )
    Bugfender.sendIssueReturningUrl(
      withTitle: "[\(String(describing: filePath.stem)):\(line) \(function)]",
      text: message.description
    )
  }
}
