// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct SettingsView: View {
  @InjectedObservable(\.navigation) private var navigation

  @State private var viewModel = SettingsViewModel()

  var body: some View {
    NavigationStack(path: $navigation.settingsPath) {
      Form {
        Section("Importing / Exporting") {
          NavigationLink(value: Navigation.SettingsView.opml, label: { Text("OPML") })
        }

        if viewModel.currentEnvironment != .appStore {
          DebugSection(environmentType: viewModel.currentEnvironment)
        }
      }
      .navigationTitle("Settings")
      .navigationDestination(for: Navigation.SettingsView.self) { section in
        switch section {
        case .opml: OPMLView()
        }
      }
    }.task(viewModel.execute)
  }
}

#if DEBUG
#Preview {
  SettingsView()
    .preview()
}
#endif
