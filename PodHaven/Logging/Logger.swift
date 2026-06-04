// Copyright Justin Bishop, 2025

import Foundation
import Logging

extension Logger {
  // MARK: - Special Logging

  // A bare level means: log remarkable errors at `level`, but still mute
  // unremarkable ones (cancellation, cancelled/timed-out URLError) down to
  // `.debug`. Reach for the closure overload when you need to override that —
  // e.g. routing cancellation to `.trace` to keep it out of the file log.
  func caughtError(
    _ header: String,
    _ error: any Error,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line,
    level: Logger.Level = .error
  ) {
    caughtError(
      header,
      error,
      file: file,
      function: function,
      line: line,
      level: { ErrorKit.isRemarkable($0) ? level : .debug }
    )
  }

  func caughtError(
    _ header: String,
    _ error: any Error,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line,
    level: (any Error) -> Logger.Level
  ) {
    let message: Logger.Message = "\(header)\n\(ErrorKit.loggableMessage(for: error))"
    self.log(level: level(error), message, file: file, function: function, line: line)
  }
}
