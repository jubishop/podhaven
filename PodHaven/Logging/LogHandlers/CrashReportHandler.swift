// Copyright Justin Bishop, 2025

import BugfenderSDK
import Foundation
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
    Bugfender.sendIssueReturningUrl(
      withTitle: "[\(String(describing: filePath.stem)):\(line) \(function)]",
      text: message.description
    )
  }
}
