// Copyright Justin Bishop, 2025

import Foundation

struct ThreadLock {
  private struct Waiter: Sendable {
    let id: UUID
    let continuation: CheckedContinuation<Void, any Error>
  }

  private struct State: Sendable {
    var isClaimed = false
    var waiters: [Waiter] = []
  }

  private let state = ThreadSafe(State())

  var isClaimed: Bool {
    state { $0.isClaimed }
  }

  func claim() -> Bool {
    state { value in
      if value.isClaimed { return false }
      value.isClaimed = true
      return true
    }
  }

  func waitForClaim() async throws {
    try Task.checkCancellation()
    if claim() { return }

    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        let acquiredImmediately: Bool? = state { value in
          if value.isClaimed == false {
            value.isClaimed = true
            return true
          }
          if Task.isCancelled {
            return false
          }
          value.waiters.append(Waiter(id: id, continuation: continuation))
          return nil
        }
        if let acquiredImmediately {
          if acquiredImmediately {
            continuation.resume()
          } else {
            continuation.resume(throwing: CancellationError())
          }
        }
      }
    } onCancel: {
      let continuation: CheckedContinuation<Void, any Error>? = state { value in
        guard let index = value.waiters.firstIndex(where: { $0.id == id }) else {
          return nil
        }
        return value.waiters.remove(at: index).continuation
      }
      continuation?.resume(throwing: CancellationError())
    }
  }

  func release() {
    var nextWaiter: CheckedContinuation<Void, any Error>?

    state { value in
      guard value.isClaimed else { return }

      if value.waiters.isEmpty {
        value.isClaimed = false
      } else {
        nextWaiter = value.waiters.removeFirst().continuation
      }
    }

    nextWaiter?.resume(returning: ())
  }
}
