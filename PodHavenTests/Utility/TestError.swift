// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@testable import PodHaven

@ReadableError
enum TestError: ReadableError {
  case assetLoadFailure(URL)
  case imageFetchFailure(URL)
  case waitForValueFailure(String)
  case waitUntilFailure(String)

  var message: String {
    switch self {
    case .assetLoadFailure(let url):
      return "Failed to load asset for url: \(url)"
    case .imageFetchFailure(let url):
      return "Failed to fetch image from URL: \(url)"
    case .waitForValueFailure(let typeName):
      return "Failed to wait for non-optional value of type: \(typeName)"
    case .waitUntilFailure(let message):
      return "Wait failure: \(message)"
    }
  }
}
