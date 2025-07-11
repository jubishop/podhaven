// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct SettingsView: View {
  @InjectedObservable(\.navigation) private var navigation

  private let viewModel = SettingsViewModel()

  var body: some View {
    NavigationStack(path: $navigation.settings.path) {
      Form {
        Section("Importing / Exporting") {
          NavigationLink(
            value: Navigation.Settings.Destination.viewType(.opml),
            label: { Text("OPML") }
          )
        }

        if AppInfo.environment != .appStore {
          DebugSection()
        }
      }
      .navigationTitle("Settings")
      .navigationDestination(
        for: Navigation.Settings.Destination.self
      ) { destination in
        navigation.settings.navigationDestination(for: destination)
      }
    }
  }
}

#if DEBUG
#Preview {
  SettingsView()
    .preview()
}
#endif
