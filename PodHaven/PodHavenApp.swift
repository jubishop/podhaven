// Copyright Justin Bishop, 2024

import SwiftUI

@main
struct PodHavenApp: App {
  @State private var alert = Alert.shared

  init() {
    setTabBarAppearance()
  }

  var body: some Scene {
    WindowGroup {
      ContentView().customAlert($alert.config)
    }
  }

  private func setTabBarAppearance() {
    let appearance = UITabBarAppearance()
    appearance.configureWithDefaultBackground()
    UITabBar.appearance().standardAppearance = appearance
    UITabBar.appearance().scrollEdgeAppearance = appearance
  }
}
