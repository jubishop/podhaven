// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

extension Container {
  var dateProvider: Factory<any DateProviding> {
    Factory(self) { DateProvider() }.cached
  }
}

private struct DateProvider: DateProviding {
  var now: Date { Date() }
}
