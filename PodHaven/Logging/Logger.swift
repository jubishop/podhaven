// Copyright Justin Bishop, 2025

import Foundation
import Logging

extension Logger {
  // MARK: - Error Logging

  func error(
    _ error: Error,
    metadata: @autoclosure () -> Logger.Metadata? = nil,
    source: @autoclosure () -> String? = nil,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
  ) {
    self.error(
      ErrorKit.loggableMessage(for: error),
      metadata: metadata(),
      source: source(),
      file: file,
      function: function,
      line: line
    )
  }

  func critical(
    _ error: Error,
    metadata: @autoclosure () -> Logger.Metadata? = nil,
    source: @autoclosure () -> String? = nil,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
  ) {
    self.critical(
      ErrorKit.loggableMessage(for: error),
      metadata: metadata(),
      source: source(),
      file: file,
      function: function,
      line: line
    )
  }
}
