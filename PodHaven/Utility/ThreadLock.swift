// Copyright Justin Bishop, 2025

import Foundation

struct ThreadLock {
  private struct State: Sendable {
    var isClaimed = false
    var waiters: [CheckedContinuation<Void, Never>] = []
  }

  private let state = ThreadSafe(State())

  var claimed: Bool {
    state { $0.isClaimed }
  }

  func claim() -> Bool {
    state { value in
      if value.isClaimed { return false }
      value.isClaimed = true
      return true
    }
  }

  func waitForClaim() async {
    if claim() {
      if Task.isCancelled {
        release()
      }
      return
    }

    await withCheckedContinuation { continuation in
      var shouldResumeImmediately = false

      state { value in
        if value.isClaimed == false {
          value.isClaimed = true
          shouldResumeImmediately = true
        } else {
          value.waiters.append(continuation)
        }
      }

      if shouldResumeImmediately {
        continuation.resume()
      }
    }

    if Task.isCancelled {
      release()
    }
  }

  func release() {
    var nextWaiter: CheckedContinuation<Void, Never>?

    state { value in
      guard value.isClaimed else { return }

      if value.waiters.isEmpty {
        value.isClaimed = false
      } else {
        nextWaiter = value.waiters.removeFirst()
      }
    }

    nextWaiter?.resume()
  }
}
