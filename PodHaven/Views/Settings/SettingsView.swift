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
      }
      .navigationTitle("Settings")
    }
  }
}

#Preview {
  SettingsView()
}
