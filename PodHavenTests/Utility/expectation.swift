// Copyright Justin Bishop, 2024

import Foundation
import Testing

public actor Fulfillment {
  private var _fulfilled: Bool = false
  public var fulfilled: Bool {
    return _fulfilled
  }
  public func callAsFunction() async {
    _fulfilled = true
  }
}

public func expectation(
  _ comment: Comment,
  is fulfillment: Fulfillment,
  in timeout: Duration = .milliseconds(100)
) async {
  let sleepDuration: Duration = .milliseconds(10)
  let tries = Int(ceil(timeout / sleepDuration))
  for _ in 0...tries {
    if await fulfillment.fulfilled {
      return
    }
    try! await Task.sleep(for: sleepDuration)
  }
  Issue.record("Expectation that: \"\(comment)\" never occurred")
}
