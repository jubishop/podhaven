// Copyright Justin Bishop, 2024

import Foundation
import Testing

public actor Fulfillment {
  private var _fulfilled: Bool = false
  public func callAsFunction() {
    _fulfilled = true
  }
}

private extension Fulfillment {
  var fulfilled: Bool {
    _fulfilled
  }
  func reset() {
    _fulfilled = false
  }
}

// This can be used two ways:
// ```
//  let fulfilled = Fulfillment()
//  await somethingDelayed() {
//    await fulfilled()
//  }
//  await expect("Something delayed", is: fulfilled, in: .milliseconds(100))
// ```
// The passed in `fulfilled` object will be automatically reset for reuse.
//
// Or:
// ```
//  await expect("Something delayed", in: .milliseconds(100)) { fulfilled in
//    await somethingDelayed() {
//      await fulfilled()
//    }
//  }
// ```
//
// Note:
//  `in:` parameter is optional, defaults to .milliseconds(100)
public func expect(
  _ comment: Comment,
  is fulfillment: Fulfillment? = nil,
  in timeout: Duration = .milliseconds(100),
  _ block: ((Fulfillment) async throws -> Void)? = nil
) async {
  guard fulfillment != nil || block != nil else {
    Issue.record(
      """
      Fulfillment of \"\(comment)\" cannot be tested: \
      either a trailing closure or Fulfillment variable must be provided.
      """
    )
    return
  }

  let actualFulfillment = fulfillment ?? Fulfillment()
  if let block = block {
    do {
      try await block(actualFulfillment)
    } catch {
      Issue.record("Fulfillment of \"\(comment)\" threw error: \(error)")
      return
    }
  }

  let startTime = ContinuousClock.now
  var timeElapsed = Duration.zero
  while timeElapsed <= timeout {
    if await actualFulfillment.fulfilled {
      await actualFulfillment.reset()
      return
    }
    timeElapsed = ContinuousClock.now - startTime
    try! await Task.sleep(for: .milliseconds(10))
  }
  Issue.record("Expected fulfillment of: \"\(comment)\" never occurred")
}
