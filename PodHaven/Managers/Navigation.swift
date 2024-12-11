// Copyright Justin Bishop, 2024

import SwiftUI

struct NavigationView: Hashable {
  private let id = UUID()
  private let builder: () -> AnyView

  init<Content: View>(@ViewBuilder _ builder: @escaping () -> Content) {
    self.builder = { AnyView(builder()) }
  }

  func callAsFunction() -> some View {
    builder()
  }

  static func == (lhs: NavigationView, rhs: NavigationView) -> Bool {
    lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

@Observable @MainActor final class Navigation: Sendable {
  static let shared = { Navigation() }()

  enum Tab {
    case settings
    case podcasts
  }

  var settingsPath = NavigationPath()
  var podcastsPath = NavigationPath()

  var currentTab: Tab = .settings {
    willSet {
      if newValue == .settings {
        settingsPath = NavigationPath()
      }
      if newValue == .podcasts {
        podcastsPath = NavigationPath()
      }
    }
  }

  private init() {}
}
