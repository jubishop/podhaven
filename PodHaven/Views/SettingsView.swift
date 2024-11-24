// Copyright Justin Bishop, 2024

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  @Environment(Navigation.self) var navigation

  let opmlType = UTType(filenameExtension: "opml", conformingTo: .xml)!

  @State private var opmlImporting = false

  var body: some View {
    NavigationStack {
      Form {
        Section("Importing / Exporting") {
          Button(
            action: {
              opmlImporting = true
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
    .fileImporter(
      isPresented: $opmlImporting,
      allowedContentTypes: [opmlType]
    ) { result in
      switch result {
      case .success(let file):
        print(file.absoluteString)
      case .failure(let error):
        print(error.localizedDescription)
      }
    }
  }
}

#Preview {
  SettingsView().environment(Navigation())
}
