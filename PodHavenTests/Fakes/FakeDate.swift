// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

@testable import PodHaven

extension Container {
  var fakeDate: Factory<FakeDate> {
    Factory(self) { FakeDate() }.scope(.cached)
  }
}

final class FakeDate: DateProviding, Sendable {
  private enum Mode: Sendable {
    case passthrough
    case manual(Date)
  }

  private let mode = ThreadSafe<Mode>(.passthrough)

  var now: Date {
    mode { current in
      switch current {
      case .passthrough:
        return Date()
      case .manual(let date):
        return date
      }
    }
  }

  func freeze(at date: Date = Date()) {
    mode { current in
      current = .manual(date)
    }
  }
}
