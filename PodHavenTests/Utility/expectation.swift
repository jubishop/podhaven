// Copyright Justin Bishop, 2024

import Foundation
import Testing

public class Fulfillment {
  private var _fulfilled: Bool = false
  public var fulfilled: Bool {
    _fulfilled
  }

  public func callAsFunction() {
    _fulfilled = true
  }
}

public func expectation(
  _ comment: Comment,
  timeout: Duration = .milliseconds(100),
  _ body: (Fulfillment) async -> Void
) async {
  let sleepDuration: Duration = .milliseconds(10)
  let tries = Int(ceil(timeout / sleepDuration))
  let fulfillment = Fulfillment()

  for _ in 0..<tries {
    await body(fulfillment)
    if fulfillment.fulfilled {
      return
    }
    try! await Task.sleep(for: sleepDuration)
  }

  Issue.record("Fulfillment of: \"\(comment)\" never occurred")
}
