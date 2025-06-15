// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

extension Container {
  var neverCalled: Factory<(String) -> Bool> {
    Factory(self) {
      var calledFunctions: [String: Bool] = [:]
      return { name in
        if calledFunctions[name] != nil { return false }

        calledFunctions[name] = true
        return true
      }
    }
    .scope(.cached)
  }
}

enum Function {
  static func neverCalled(
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
  ) -> Bool {
    let neverCalled = Container.shared.neverCalled()
    return neverCalled("\(file):\(function):\(line)")
  }
}
