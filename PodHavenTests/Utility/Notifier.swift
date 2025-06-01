// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

actor Notifier {
  private static var continuations: [Notification.Name: AsyncStream<Notification>.Continuation] =
    [:]

  static func set(_ name: Notification.Name, _ continuation: AsyncStream<Notification>.Continuation)
  {
    self.continuations[name] = continuation
  }

  static func get(_ name: Notification.Name) async throws -> AsyncStream<Notification>.Continuation
  {
    try await TestHelpers.waitForValue { continuations[name] }
  }
}
