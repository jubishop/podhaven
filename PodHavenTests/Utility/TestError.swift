// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@testable import PodHaven

@ReadableError
enum TestError: ReadableError {
  case assetLoadFailure(MediaURL)
  case waitForValueFailure(String)
  case waitUntilFailure

  var message: String {
    switch self {
    case .assetLoadFailure(let url):
      return "Failed to load asset from URL: \(url)"
    case .waitForValueFailure(let typeName):
      return "Failed to wait for non-optional value of type: \(typeName)"
    case .waitUntilFailure:
      return "Failed to wait until condition evaluates to true"
    }
  }
}
