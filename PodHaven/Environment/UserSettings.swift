// Copyright Justin Bishop, 2025

import FactoryKit
import Sharing
import SwiftUI

extension Container {
  var userSettings: Factory<UserSettings> {
    Factory(self) { UserSettings() }.scope(.cached)
  }
}

@Observable class UserSettings {
  @ObservationIgnored @Shared(.appStorage("shrinkPlayBarOnScroll")) var shrinkPlayBarOnScroll = true

  fileprivate init() {}
}
