// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct SettingsView: View {
  @InjectedObservable(\.navigation) private var navigation
  @InjectedObservable(\.userSettings) private var userSettings

  private let viewModel = SettingsViewModel()

  var body: some View {
    IdentifiableNavigationStack(manager: navigation.settings) {
      Form {
        Section("Appearance") {
          Toggle("Hide Tab Bar on Scroll", isOn: $userSettings.hideTabBarOnScroll)
        }

        Section("Importing / Exporting") {
          NavigationLink(
            value: Navigation.Destination.settingsSection(.opml),
            label: { Text("OPML") }
          )
        }

        if AppInfo.environment != .appStore {
          DebugSection()
        }
      }
      .navigationTitle("Settings")
    }
  }
}

#if DEBUG
#Preview {
  SettingsView()
    .preview()
}
#endif
