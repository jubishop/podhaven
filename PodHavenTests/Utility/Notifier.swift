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
    var count = 0
    while count < 10 {
      if let continuation = continuations[name] { return continuation }
      try? await Task.sleep(nanoseconds: 10_000_000)
      count += 1
    }
    Assert.fatal("Could not find continuation for \(name)")
  }
}
