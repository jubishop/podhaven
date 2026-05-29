// Copyright Justin Bishop, 2026

import Foundation

protocol DateProviding: Sendable {
  var now: Date { get }
}
