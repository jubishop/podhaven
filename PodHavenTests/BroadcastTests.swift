// Copyright Justin Bishop, 2026

import Foundation
import SwiftUI
import Testing

@testable import PodHaven

@Suite("of Broadcast tests")
struct BroadcastTests {
  // The Observation contract notifies synchronously on the main actor, and
  // SwiftUI List edits (.onMove/.onDelete) require the bound collection's
  // change to be observed within the gesture transaction. A main-actor write
  // must wake observers before control returns, not a runloop turn later.
  @Test("notifies observers synchronously when mutated on the main actor")
  @MainActor func notifiesObserversSynchronouslyOnMain() {
    let broadcast = Broadcast<Int>(0)

    let notified = ThreadSafe(false)
    withObservationTracking {
      _ = broadcast.current
    } onChange: {
      notified(true)
    }

    broadcast.new(1)

    #expect(notified())
  }

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

  @Test("notifyAlways policy delivers writes that leave the value unchanged")
  func notifyAlwaysDeliversNoOpWrites() async throws {
    let broadcast = Broadcast<Int>(0, policy: .notifyAlways)
    let stream = broadcast.stream()

    broadcast.new(0)  // identical to current — still broadcasts
    broadcast.new(0)  // identical — still broadcasts
    broadcast.update { _ in }  // unchanged — still broadcasts

    var received: [Int] = []
    for await value in stream.prefix(4) {
      received.append(value)
    }
    #expect(received == [0, 0, 0, 0])
  }

  @Test("@Broadcasted deduplicates no-op writes for an Equatable value")
  func broadcastedDeduplicatesEquatableWrites() async throws {
    let fixture = BroadcastedFixture()
    let stream = fixture.$value.stream()

    fixture.$value.new(0)  // identical to current — must not broadcast
    fixture.$value.new(1)  // changed — broadcasts
    fixture.$value.new(1)  // identical — must not broadcast
    fixture.$value.new(2)  // changed — broadcasts

    var received: [Int] = []
    for await value in stream.prefix(3) {
      received.append(value)
    }
    #expect(received == [0, 1, 2])
  }

  @Test("@Broadcasted(duplicates: .notifyAlways) delivers every write")
  func broadcastedNotifyAlwaysDeliversEveryWrite() async throws {
    let fixture = NotifyAlwaysFixture()
    let stream = fixture.$value.stream()

    fixture.$value.new(0)  // identical to current — still broadcasts
    fixture.$value.new(0)  // identical — still broadcasts
    fixture.$value.new(1)  // changed — broadcasts

    var received: [Int] = []
    for await value in stream.prefix(4) {
      received.append(value)
    }
    #expect(received == [0, 0, 0, 1])
  }

  @Test("PersistedBroadcast's wrappedValue setter suppresses same-value writes")
  func persistedBroadcastSetterSuppressesIdenticalWrites() async throws {
    let fixture = PersistedBroadcastFixture()
    let stream = fixture.$value.stream()

    fixture.value = 0  // identical to current — must not broadcast
    fixture.value = 1  // changed — broadcasts
    fixture.value = 1  // identical — must not broadcast
    fixture.value = 2  // changed — broadcasts

    var received: [Int] = []
    for await value in stream.prefix(3) {
      received.append(value)
    }
    #expect(received == [0, 1, 2])
  }

  @Test("binding's setter suppresses same-value writes")
  func bindingSetterSuppressesIdenticalWrites() async throws {
    let broadcast = Broadcast<Int>(0)
    let stream = broadcast.stream()
    let binding = broadcast.binding

    binding.wrappedValue = 0  // identical to current — must not broadcast
    binding.wrappedValue = 1  // changed — broadcasts
    binding.wrappedValue = 1  // identical — must not broadcast
    binding.wrappedValue = 2  // changed — broadcasts

    var received: [Int] = []
    for await value in stream.prefix(3) {
      received.append(value)
    }
    #expect(received == [0, 1, 2])
  }
}

// Verifies the @Broadcasted property wrapper resolves to the
// Equatable-deduplicating init for Equatable values.
private struct BroadcastedFixture {
  @Broadcasted var value: Int = 0
}

// Opts out of dedup via the explicit policy — the path SharedState.onDeck uses.
private struct NotifyAlwaysFixture {
  @Broadcasted(duplicates: .notifyAlways) var value: Int = 0
}

// Exercises `PersistedBroadcast`'s `wrappedValue` setter, which routes through
// `Broadcast.new` from inside a `<T: DefaultsStorable>` generic context.
private struct PersistedBroadcastFixture {
  @PersistedBroadcast("broadcast-tests-dedupe", store: FakeKeyValueStore())
  var value: Int = 0
}
