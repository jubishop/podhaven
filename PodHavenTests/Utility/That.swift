// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Tagged

@testable import PodHaven

enum That {
  static func eventually(
    maxAttempts: Int = 100,
    delay: Duration = .milliseconds(10),
    _ block: @Sendable @escaping () async throws -> Bool
  ) async throws -> Bool {
    var attempts = 0
    while attempts < maxAttempts {
      if try await block() {
        return true
      }
      try await Task.sleep(for: delay)
      attempts += 1
    }
    return false
  }
}
