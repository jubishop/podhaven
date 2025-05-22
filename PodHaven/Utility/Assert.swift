import Foundation
import Logging
import System

#if !DEBUG
import Sentry
#endif

struct Assert {
  private static let shared: Assert = Assert()

  static func fatal(
    _ message: String,
    file: FilePath = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) -> Never {
    shared.fatal(message, file: file, function: function, line: line)
  }

  static func precondition(
    _ condition: Bool,
    _ message: String,
    file: FilePath = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    shared.precondition(condition, message, file: file, function: function, line: line)
  }

  fileprivate init() {}

  func fatal(
    _ message: String,
    file: FilePath = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) -> Never {
    #if !DEBUG
    SentrySDK.capture(message: message)
    #endif

    fatalError(
      """
      ----------------------------------------------------------------------------------------------
      ❗️ Fatal from: [\(String(describing: file.stem)):\(line) \(function)]
      \(message)
      ----------------------------------------------------------------------------------------------
      """
    )
  }

  func precondition(
    _ condition: Bool,
    _ message: String,
    file: FilePath = #fileID,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    guard !condition else { return }

    #if !DEBUG
    SentrySDK.capture(message: message)
    #endif

    fatalError(
      """
      ----------------------------------------------------------------------------------------------
      ❗️ Failed precondition from: [\(String(describing: file.stem)):\(line) \(function)]
      \(message)
      ----------------------------------------------------------------------------------------------
      """
    )
  }
}
