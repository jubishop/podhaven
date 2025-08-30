// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct SettingsView: View {
  @InjectedObservable(\.navigation) private var navigation

  private let viewModel = SettingsViewModel()

  var body: some View {
    IdentifiableNavigationStack(manager: navigation.settings) {
      Form {
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
      .navigationDestination(
        for: Navigation.Destination.self,
        destination: navigation.navigationDestination
      )
    }
  }
}

#if DEBUG
#Preview {
  SettingsView()
    .preview()
}
#endif
