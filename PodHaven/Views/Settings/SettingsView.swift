// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct SettingsView: View {
  @InjectedObservable(\.navigation) private var navigation

  private let viewModel = SettingsViewModel()

  var body: some View {
    NavigationStack(path: $navigation.settingsPath) {
      Form {
        Section("Importing / Exporting") {
          NavigationLink(value: Navigation.SettingsView.opml, label: { Text("OPML") })
        }

        if AppInfo.environment != .appStore {
          DebugSection()
        }
      }
      .navigationTitle("Settings")
      .navigationDestination(
        for: Navigation.SettingsView.self,
        destination: navigation.settingsView
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
