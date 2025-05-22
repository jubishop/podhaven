import Foundation
import Logging

#if !DEBUG
import Sentry
#endif

struct Assert {
  private static let shared: Assert = Assert()

  static func fatal(
    _ message: String,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) -> Never {
    shared.fatal(message, file: file, function: function, line: line)
  }

  static func precondition(
    _ condition: Bool,
    _ message: String,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    shared.precondition(condition, message, file: file, function: function, line: line)
  }

  fileprivate init() {}

  func fatal(
    _ message: String,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) -> Never {
    #if !DEBUG
    SentrySDK.capture(message: message)
    #endif

    fatalError(
      """
      ----------------------------------------------------------------------------------------------
      ❗️ Fatal from: [\(LogKit.fileName(from: file)):\(line) \(function)]
      \(message)

      🧱 Call stack:
        \(StackTracer.capture(limit: 20, drop: 1).joined(separator: "\n  "))
      ----------------------------------------------------------------------------------------------
      """
    )
  }

  func precondition(
    _ condition: Bool,
    _ message: String,
    file: String = #file,
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
      ❗️ Failed precondition from: [\(LogKit.fileName(from: file)):\(line) \(function)]
      \(message)

      🧱 Call stack:
        \(StackTracer.capture(limit: 20, drop: 1).joined(separator: "\n  "))
      ----------------------------------------------------------------------------------------------
      """
    )
  }
}
