// Copyright Justin Bishop, 2024

import SwiftUI

@Observable @MainActor final class Navigation : Sendable {
  enum Tab {
    case settings
    case upNext
    case podcasts
  }

  var currentTab: Tab = .settings
}
