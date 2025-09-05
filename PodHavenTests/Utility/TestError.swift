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
  case unexpectedCallCount(expected: Int, actual: Int, type: String)
  case unexpectedCall(type: String, calls: [String])
  case unexpectedCallOrder(expected: [String], actual: [String])
  case unexpectedParameters(String)
  case fileNotFound(URL)
  case directoryNotFound(URL)
  case moveFailed(from: URL, to: URL, underlying: Error)

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
    case .unexpectedCallCount(let expected, let actual, let type):
      return "Expected \(expected) calls of type \(type), but got \(actual)"
    case .unexpectedCall(let type, let calls):
      return "Expected no calls of type \(type), but got: \(calls.joined(separator: ", "))"
    case .unexpectedCallOrder(let expected, let actual):
      return
        """
        Expected call order: \(expected.joined(separator: " -> ")), \
        but got: \(actual.joined(separator: " -> "))
        """
    case .unexpectedParameters(let message):
      return "Unexpected parameters: \(message)"
    case .fileNotFound(let url):
      return "File not found at URL: \(url)"
    case .directoryNotFound(let url):
      return "Directory not found at URL: \(url)"
    case .moveFailed(let from, let to, let underlying):
      return "Move failed from \(from) to \(to): \(underlying)"
    }
  }
}
