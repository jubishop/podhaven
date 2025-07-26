// Copyright Justin Bishop, 2025

import Foundation

protocol Sleepable: Sendable {
  func sleep(for duration: Duration) async throws
}
