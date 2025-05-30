// Copyright Justin Bishop, 2025

import Foundation

actor Notifier {
  private static var continuations: [Notification.Name: AsyncStream<Notification>.Continuation] =
    [:]

  static func set(_ name: Notification.Name, _ continuation: AsyncStream<Notification>.Continuation)
  {
    self.continuations[name] = continuation
  }

  static func get(_ name: Notification.Name) async -> AsyncStream<Notification>.Continuation {
    while continuations[name] == nil {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return continuations[name]!
  }
}
