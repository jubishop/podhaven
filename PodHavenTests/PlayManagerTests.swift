// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

actor ContinuationBox {
  var continuation: AsyncStream<Notification>.Continuation?
  func setContinuation(_ continuation: AsyncStream<Notification>.Continuation) {
    self.continuation = continuation
  }
  func waitForContinuation() async -> AsyncStream<Notification>.Continuation {
    while continuation == nil {
      try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms backoff
    }
    return continuation!
  }
}

@Suite("of PlayManager tests", .container)
struct PlayManagerTests {
  @Test("example")
  func example() async throws {
    let box = ContinuationBox()
    Container.shared.notifications.context(.test) {
      { name in
        print("getting notification for \(name)")
        return AsyncStream { continuation in
          Task { await box.setContinuation(continuation) }
        }
      }
    }
    let playManager = Container.shared.playManager()
    await playManager.start()
    let continuation = await box.waitForContinuation()
    continuation.yield(Notification(name: .init("Test")))

    #expect("Test" == "Test")
  }
}
