// Copyright Justin Bishop, 2024

import SwiftUI

class Navigation: ObservableObject {
  enum Tab {
    case settings
    case upNext
  }

  @Published var currentTab: Tab = .settings
}
