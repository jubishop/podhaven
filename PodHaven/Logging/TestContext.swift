#if DEBUG
// Copyright Justin Bishop, 2025

import Foundation

/// Utility for tracking test context information for enhanced logging during tests
enum TestContext {
  @TaskLocal static var current: String?

  /// Execute a block with a specific test context
  static func withContext<T: Sendable>(_ testName: String, _ block: @Sendable () async throws -> T)
    async rethrows -> T
  {
    try await Self.$current.withValue(testName) {
      try await block()
    }
  }
}
#endif
