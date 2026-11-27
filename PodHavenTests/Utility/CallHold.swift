// Copyright Justin Bishop, 2026

import Foundation

@testable import PodHaven

// While held, every call that reaches `park()` waits there, as if another
// transaction held the database writer, until `release()` resumes them all.
final class CallHold: Sendable {
  private struct State {
    var held = false
    var parked: [CheckedContinuation<Void, Never>] = []
  }

  private let state = ThreadSafe(State())

  func hold() {
    state { $0.held = true }
  }

  func park() async {
    guard state({ $0.held }) else { return }
    await withCheckedContinuation { continuation in
      let parked = state { state in
        guard state.held else { return false }
        state.parked.append(continuation)
        return true
      }
      if !parked { continuation.resume() }
    }
  }

  func release() {
    let parked = state { state in
      state.held = false
      let parked = state.parked
      state.parked = []
      return parked
    }
    for continuation in parked { continuation.resume() }
  }

  // Resumes the call that parked first, as the writer runs its oldest queued
  // transaction, and keeps holding the rest.
  func releaseFirst() {
    let first = state { state in state.parked.isEmpty ? nil : state.parked.removeFirst() }
    first?.resume()
  }

  func waitForParked(count: Int = 1) async throws {
    try await Wait.until(
      { self.state { $0.parked.count } >= count },
      { "Expected at least \(count) parked calls, got \(self.state { $0.parked.count })" }
    )
  }
}
