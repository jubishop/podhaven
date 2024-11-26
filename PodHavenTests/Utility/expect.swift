// Copyright Justin Bishop, 2024

import Foundation
import Testing

public actor Fulfillment {
  private var _fulfilled: Bool = false
  public var fulfilled: Bool {
    _fulfilled
  }
  public func reset() {
    _fulfilled = false
  }
  public func callAsFunction() {
    _fulfilled = true
  }
}

public func expect(
  _ comment: Comment,
  in timeout: Duration = .milliseconds(100),
  _ block: (Fulfillment) async throws -> Void
) async {
  let fulfillment = Fulfillment()
  do {
    try await block(fulfillment)
  } catch {
    Issue.record("Fulfillment of \"\(comment)\" threw error: \(error)")
  }

  let sleepDuration: Duration = .milliseconds(10)
  let tries = Int(ceil(timeout / sleepDuration))
  for _ in 0...tries {
    if await fulfillment.fulfilled {
      return
    }
    try! await Task.sleep(for: sleepDuration)
  }
  Issue.record("Expected fulfillment of: \"\(comment)\" never occurred")
}
