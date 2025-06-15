import FactoryKit
import Foundation
import Logging
import System

enum Assert {
  private static let log = Log.as("Assert", level: .critical)

  static func neverCalled(
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
  ) {
    Assert.precondition(
      Function.neverCalled(file: file, function: function, line: line),
      "\(file):\(function):\(line) has already been called?"
    )
  }

  static func fatal(
    _ message: String,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
  ) -> Never {
    log.critical(
      Logger.Message(stringLiteral: message),
      file: file,
      function: function,
      line: line
    )

    fatalError(
      """
      ----------------------------------------------------------------------------------------------
      ❗️ Fatal from: [\(String(describing: FilePath(file).stem)):\(line) \(function)]
      \(message)
      ----------------------------------------------------------------------------------------------
      """
    )
  }

  static func precondition(
    _ condition: Bool,
    _ message: String,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
  ) {
    guard !condition else { return }

    fatal(message, file: file, function: function, line: line)
  }
}
