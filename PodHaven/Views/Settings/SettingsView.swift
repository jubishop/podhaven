// Copyright Justin Bishop, 2024

import SwiftUI

struct SettingsView: View {
  var body: some View {
    NavigationStack {
      Form {
        Section("Importing / Exporting") {
          NavigationLink(
            destination: OPMLView(),
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
    }
  }
}

#Preview {
  Preview { SettingsView() }
}
