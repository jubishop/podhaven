// Copyright Justin Bishop, 2024

import Foundation
import Testing

public actor Fulfillment {
  private var _fulfilled: Bool = false
  public var fulfilled: Bool {
    return _fulfilled
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
  is fulfillment: Fulfillment,
  in timeout: Duration = .milliseconds(100)
) async {
  let sleepDuration: Duration = .milliseconds(10)
  let tries = Int(ceil(timeout / sleepDuration))
  for _ in 0...tries {
    if await fulfillment.fulfilled {
      await fulfillment.reset()
      return
    }
    try! await Task.sleep(for: sleepDuration)
  }
  Issue.record("Expected fulfillment of: \"\(comment)\" never occurred")
}
