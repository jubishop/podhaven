// Copyright Justin Bishop, 2024

import SwiftUI

@Observable
class Navigation {
  enum Tab {
    case settings
    case upNext
  }

  var currentTab: Tab = .settings
}
