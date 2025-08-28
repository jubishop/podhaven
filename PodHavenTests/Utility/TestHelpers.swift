// Copyright Justin Bishop, 2025

import Foundation
import Testing

@testable import PodHaven

enum TestHelpers {
  /// Execute a test with automatic test context tracking for enhanced logging
  static func withTestContext<T: Sendable>(
    function: String = #function,
    _ block: @Sendable () async throws -> T
  ) async rethrows -> T {
    try await TestContext.withContext(cleanTestFunctionName(function), block)
  }

  /// Clean up Swift Testing function names to make them more readable
  private static func cleanTestFunctionName(_ function: String) -> String {
    var cleaned = function

    // Remove parentheses and parameters
    if let parenIndex = cleaned.firstIndex(of: "(") {
      cleaned = String(cleaned[..<parenIndex])
    }

    return cleaned
  }
}
