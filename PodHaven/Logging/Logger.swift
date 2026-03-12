// Copyright Justin Bishop, 2025

import Foundation
import Logging

extension Logger {
  // MARK: - Special Logging

  func caughtError(
    _ header: String,
    _ error: any Error,
    remarkable: Logger.Level = .error,
    mundane: Logger.Level = .info,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
  ) {
    Assert.precondition(
      mundane <= remarkable,
      "mundane level (\(mundane)) must not exceed remarkable level (\(remarkable))"
    )
    let message: Logger.Message = "\(header)\n\(ErrorKit.loggableMessage(for: error))"
    if ErrorKit.isRemarkable(error) {
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
    line: UInt = #line
  ) {
    Assert.precondition(
      mundane <= remarkable,
      "mundane level (\(mundane)) must not exceed remarkable level (\(remarkable))"
    )
    let message = ErrorKit.loggableMessage(for: error)
    if ErrorKit.isRemarkable(error) {
      self.log(level: remarkable, message, file: file, function: function, line: line)
    } else {
      self.log(level: mundane, message, file: file, function: function, line: line)
    }
  }

  func `catch`<T>(
    _ operation: () throws -> T
  ) -> T? {
    do {
      return try operation()
    } catch {
      self.error(error)
      return nil
    }
  }

  func `catch`<T>(
    _ operation: @Sendable () async throws -> T
  ) async -> T? {
    do {
      return try await operation()
    } catch {
      self.error(error)
      return nil
    }
  }
}
