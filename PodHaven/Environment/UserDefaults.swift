// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

extension Container {
  var standardDefaults: Factory<any KeyValueStore> {
    Factory(self) { UserDefaults.standard }
      .scope(.cached)
  }

  var sharedDefaults: Factory<any KeyValueStore> {
    Factory(self) {
      guard let defaults = UserDefaults(suiteName: "group.podhaven.shared") else {
        Assert.fatal("UserDefaults not found for group.podhaven.shared")
      }
      return defaults
    }
    .scope(.cached)
  }
}
