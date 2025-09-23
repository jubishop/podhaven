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
      .playBarSafeAreaInset()
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
