// Copyright Justin Bishop, 2025

import Foundation

struct Err: Error, LocalizedError, Sendable {
  private let message: String

  init(
    _ message: String,
    file: StaticString = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    self.message = message

    #if DEBUG
    let fileName = "\(file)".components(separatedBy: "/").last ?? "\(file)"
    let stackTrace = StackTracer.capture(limit: 10, drop: 1).joined(separator: "\n")

    print(
      """
      ----------------------------------------------------------------------------------------------
      ⚡️ Error thrown from: [\(fileName):\(line) \(function)]:
      \(errorDescription)

      🧱 Call stack:
      \(stackTrace)

      ----------------------------------------------------------------------------------------------
      """
    )
    #endif
  }

  var errorDescription: String { message }
  var localizedDescription: String { errorDescription }
}
