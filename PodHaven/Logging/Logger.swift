// Copyright Justin Bishop, 2025

import Foundation
import Logging

extension Logger {
  // MARK: - Special Logging

  func caughtError(
    _ header: String,
    _ error: any Error,
    remarkable: Logger.Level = .error,
    mundane: Logger.Level = .trace,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line,
    isRemarkable: (any Error) -> Bool = ErrorKit.isRemarkable
  ) {
    Assert.precondition(
      mundane <= remarkable,
      "mundane level (\(mundane)) must not exceed remarkable level (\(remarkable))"
    )
    let message: Logger.Message = "\(header)\n\(ErrorKit.loggableMessage(for: error))"
    if isRemarkable(error) {
      self.log(level: remarkable, message, file: file, function: function, line: line)
    } else {
      self.log(level: mundane, message, file: file, function: function, line: line)
    }
  }

  func error(
    _ error: any Error,
    remarkable: Logger.Level = .error,
    mundane: Logger.Level = .info,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line,
    isRemarkable: (any Error) -> Bool = ErrorKit.isRemarkable
  ) {
    Assert.precondition(
      mundane <= remarkable,
      "mundane level (\(mundane)) must not exceed remarkable level (\(remarkable))"
    )
    let message = ErrorKit.loggableMessage(for: error)
    if isRemarkable(error) {
      self.log(level: remarkable, message, file: file, function: function, line: line)
    } else {
      self.log(level: mundane, message, file: file, function: function, line: line)
    }
  }

}
