// Copyright Justin Bishop, 2024

import SwiftUI

struct SettingsView: View {
  @Environment(Navigation.self) var navigation

  var body: some View {
    @Bindable var navigation = navigation
    NavigationStack(path: $navigation.settingsPath) {
      Form {
        Section("Importing / Exporting") {
          NavigationLink(
            value: NavigationView { OPMLView() },
            label: { Text("OPML") }
          )
        }

        #if DEBUG
          Section("Debugging") {
            Button("Clear DB") {
              Task {
                try AppDatabase.shared.db.write { db in
                  try Podcast.deleteAll(db)
                }
              }
            }
          }
        #endif
      }
      .navigationTitle("Settings")
      .navigationDestination(for: NavigationView.self) { view in view() }
    }
  }
}

#Preview {
  Preview { SettingsView() }
}
