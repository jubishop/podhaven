// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@testable import PodHaven

@ReadableError
enum TestError: ReadableError {
  case waitForValueFailure(String)
  case waitUntilFailure

  var message: String {
    switch self {
    case .waitForValueFailure(let typeName):
      return "Failed to wait for non-optional value of type: \(typeName)"
    case .waitUntilFailure:
      return "Failed to wait until condition evaluates to true"
    }
  }
}
