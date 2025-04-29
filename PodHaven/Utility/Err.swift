// Copyright Justin Bishop, 2025

import Foundation

struct Err: Error, LocalizedError, Sendable {
  static func msg(_ message: String) -> Self {
    Err(message)
  }

  private let message: String
  fileprivate init(_ message: String) {
    self.message = message

    #if DEBUG
    debugPrint()
    #endif
  }

  private func debugPrint(
    file: StaticString = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    let fileName = "\(file)".components(separatedBy: "/").last ?? "\(file)"
    print(
      """
      ⚡️ Error from: [\(fileName):\(line) \(function)]:
      \(errorDescription)
      """
    )
  }

  var errorDescription: String { message }
  var localizedDescription: String { errorDescription }
}
