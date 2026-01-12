// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro
import Tagged

@ReadableError
enum QueueError: ReadableError {
  case incompleteReorder(expected: Int, actual: Int)

  var message: String {
    switch self {
    case .incompleteReorder(let expected, let actual):
      return
        """
        Queue reordering requires all queued episodes
          Expected max queueOrder: \(expected)
          Actual max queueOrder: \(actual)
        """
    }
  }
}
