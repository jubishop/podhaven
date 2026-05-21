// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("of Broadcast tests")
struct BroadcastTests {
  @Test("new(_:) suppresses re-publishes of an unchanged Equatable value")
  func newSuppressesIdenticalRepublishes() async throws {
    let broadcast = Broadcast<Int>(0)
    // stream() buffers the bootstrap value (0) before any new() call lands.
    let stream = broadcast.stream()

    broadcast.new(0)  // identical to current — must not broadcast
    broadcast.new(1)  // changed — broadcasts
    broadcast.new(1)  // identical — must not broadcast
    broadcast.new(2)  // changed — broadcasts
    broadcast.new(2)  // identical — must not broadcast

    var received: [Int] = []
    for await value in stream.prefix(3) {
      received.append(value)
    }
    #expect(received == [0, 1, 2])
  }

  @Test("update(_:) suppresses transforms that leave an Equatable value unchanged")
  func updateSuppressesNoOpTransforms() async throws {
    let broadcast = Broadcast<Int>(0)
    let stream = broadcast.stream()

    broadcast.update { _ in }  // value unchanged — must not broadcast
    broadcast.update { $0 = 5 }  // changed — broadcasts
    broadcast.update { $0 = 5 }  // re-assigns the same value — must not broadcast
    broadcast.update { $0 += 1 }  // changed — broadcasts

    var received: [Int] = []
    for await value in stream.prefix(3) {
      received.append(value)
    }
    #expect(received == [0, 5, 6])
  }
}
