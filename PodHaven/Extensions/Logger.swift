// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation
import OSLog

extension Logger {
  func logError(
    _ error: Throwable & Catching,
    file: String = #file,
    function: String = #function,
    line: Int = #line
  ) {
    let fileName = "\(file)".components(separatedBy: "/").last ?? "\(file)"
    let stackTrace = StackTracer.capture(limit: 10, drop: 1).joined(separator: "\n")
    let errorChain = ErrorKit.errorChainDescription(for: error)

    self.error(
      """
      ----------------------------------------------------------------------------------------------
      ⚡️ Error thrown from: [\(fileName):\(line) \(function)]:
        \(errorChain)

      🧱 Call stack:
        \(stackTrace)
      ----------------------------------------------------------------------------------------------
      """
    )
  }
}
