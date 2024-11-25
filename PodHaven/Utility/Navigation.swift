// Copyright Justin Bishop, 2024

import SwiftUI

@Observable @MainActor final class Navigation {
  enum Tab {
    case settings
    case upNext
  }

  var currentTab: Tab = .settings
}
