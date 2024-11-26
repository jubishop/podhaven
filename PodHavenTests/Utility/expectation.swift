// Copyright Justin Bishop, 2024

import Foundation
import Testing

public class Fulfillment {
  var count: Int = 0

  func callAsFunction(_ count: Int = 1) {
    self.count += count
  }
}

public func expectation(
  _ comment: Comment,
  timeout: Duration = .seconds(0.1),
  expectedCount: Int = 1,
  _ body: (Fulfillment) async -> Void
) async {
  let sleepDuration: Duration = .seconds(0.01)
  let tries = Int(ceil(timeout / sleepDuration))
  let fulfillment = Fulfillment()

  for _ in 0..<tries {
    await body(fulfillment)
    if fulfillment.count == expectedCount {
      return
    }
    try! await Task.sleep(for: sleepDuration)
  }

  if fulfillment.count == 0 {
    Issue.record("Fulfillment of: \"\(comment)\" never occurred")
  } else {
    Issue.record(
      """
      Fulfillment of: \"\(comment)\" failed \
      with count: \(fulfillment.count), \
      expected: \(expectedCount)
      """
    )
  }
}
