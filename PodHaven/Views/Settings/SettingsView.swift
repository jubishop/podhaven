// Copyright Justin Bishop, 2024

import SwiftUI

struct SettingsView: View {
  @State private var navigation = Navigation.shared

  var body: some View {
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
                try AppDB.shared.db.write { db in
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
