// Copyright Justin Bishop, 2024

import SwiftUI

struct SettingsView: View {
  enum Sections {
    case opml
  }

  @State private var navigation = Navigation.shared

  var body: some View {
    NavigationStack(path: $navigation.settingsPath) {
      Form {
        Section("Importing / Exporting") {
          NavigationLink(value: Sections.opml, label: { Text("OPML") })
        }

        #if DEBUG
          DebugSection()
        #endif
      }
      .navigationTitle("Settings")
      .navigationDestination(for: Sections.self) { section in
        switch section {
        case .opml: OPMLView()
        }
      }
    }
  }
}

#Preview {
  Preview { SettingsView() }
}
