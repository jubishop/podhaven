// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

extension Container {
  var standardDefaults: Factory<any KeyValueStore> {
    Factory(self) { UserDefaults.standard }
  }

  var sharedDefaults: Factory<any KeyValueStore> {
    Factory(self) {
      guard let defaults = UserDefaults(suiteName: AppInfo.appGroupID) else {
        Assert.fatal("UserDefaults not found for \(AppInfo.appGroupID)")
      }
      return defaults
    }
    .scope(.cached)
  }
}
