// Copyright Justin Bishop, 2024

import SwiftUI

struct SettingsView: View {
  @EnvironmentObject var navigation: Navigation

  var body: some View {
    NavigationStack {
      Form {
        Section("Importing / Exporting") {
          Button(
            action: {
              // TODO: Import OPML
            },
            label: { Text("Import OPML") }
          )
        }
        Section("Navigating") {
          Button(
            action: { navigation.currentTab = .upNext },
            label: { Text("Go to UpNext") }
          )
        }
      }
      .navigationTitle("Settings")
    }
  }
}

#Preview {
  SettingsView().environmentScaffolding()
}
