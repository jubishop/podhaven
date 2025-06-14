// Copyright Justin Bishop, 2025

import Foundation

extension Thread {
  static var id: String {
    "\(current)".hashTo(4)
  }
}
