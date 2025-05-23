import Foundation
import Logging
import System

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
