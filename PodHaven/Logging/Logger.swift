// Copyright Justin Bishop, 2025

import Foundation
import Logging

#if !DEBUG
import Sentry
#endif

extension Logger {
  // MARK: - Sentry Reporting

  func report(
    _ message: @autoclosure () -> Logger.Message,
    metadata: @autoclosure () -> Logger.Metadata? = nil,
    source: @autoclosure () -> String? = nil,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
  ) {
    #if !DEBUG
    SentrySDK.capture(message: message)
    #endif

    critical(
      message(),
      metadata: metadata(),
      source: source(),
      file: file,
      function: function,
      line: line
    )
  }

  func report(
    _ error: Error,
    metadata: @autoclosure () -> Logger.Metadata? = nil,
    source: @autoclosure () -> String? = nil,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
  ) {
    #if !DEBUG
    SentrySDK.capture(error: error)
    #endif

    critical(
      ErrorKit.loggableMessage(for: error),
      metadata: metadata(),
      source: source(),
      file: file,
      function: function,
      line: line
    )
  }
}
