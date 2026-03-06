// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

extension Container {
  var standardDefaults: Factory<any KeyValueStore> {
    Factory(self) { UserDefaults.standard }
      .scope(.cached)
  }
}
