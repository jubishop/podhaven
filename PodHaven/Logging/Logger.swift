// Copyright Justin Bishop, 2025

import Foundation
import Logging

extension Logger {
  // MARK: - Special Logging

  func caughtError(
    _ header: String,
    _ error: any Error,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line,
    level: (any Error) -> Logger.Level = { _ in .error }
  ) {
    let message: Logger.Message = "\(header)\n\(ErrorKit.loggableMessage(for: error))"
    let resolvedLevel = ErrorKit.isRemarkable(error) ? level(error) : .debug
    self.log(level: resolvedLevel, message, file: file, function: function, line: line)
  }

  func error(
    _ error: any Error,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line,
    level: (any Error) -> Logger.Level = { _ in .error }
  ) {
    let message = ErrorKit.loggableMessage(for: error)
    let resolvedLevel = ErrorKit.isRemarkable(error) ? level(error) : .debug
    self.log(level: resolvedLevel, message, file: file, function: function, line: line)
  }

}
