// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@testable import PodHaven

@ReadableError
enum TestError: ReadableError {
  case waitForValueFailure(String)

  var message: String {
    switch self {
    case .waitForValueFailure(let typeName):
      return "Failed to wait for non-optional value of type: \(typeName)"
    }
  }
}
