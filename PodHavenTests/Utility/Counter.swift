// Copyright Justin Bishop, 2024

import Foundation

actor Counter: Sendable {
  private(set) var counter: Int = 0
  func increment() {
    counter += 1
  }
}
