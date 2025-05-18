// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct SettingsView: View {
  @InjectedObservable(\.navigation) private var navigation

  var body: some View {
    NavigationStack(path: $navigation.settingsPath) {
      Form {
        Section("Importing / Exporting") {
          NavigationLink(value: Navigation.SettingsView.opml, label: { Text("OPML") })
        }

        #if DEBUG
        DebugSection()
        #endif
      }
      .navigationTitle("Settings")
      .navigationDestination(for: Navigation.SettingsView.self) { section in
        switch section {
        case .opml: OPMLView()
        }
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
