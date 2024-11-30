// Copyright Justin Bishop, 2024

import SwiftUI

struct SettingsView: View {
  @Environment(Navigation.self) var navigation

  @State private var opmlViewModel = OPMLViewModel()

  var body: some View {
    NavigationStack {
      Form {
        Section("Importing / Exporting") {
          Button(
            action: {
              #if targetEnvironment(simulator)
                let url = Bundle.main.url(
                  forResource: "podcasts",
                  withExtension: "opml"
                )!
                opmlViewModel.importOPMLFile(url)
              #else
                opmlViewModel.opmlImporting = true
              #endif
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
      isPresented: $opmlViewModel.opmlImporting,
      allowedContentTypes: [opmlViewModel.opmlType],
      onCompletion: opmlViewModel.opmlFileImporterCompletion
    )
    .sheet(item: $opmlViewModel.opmlFile) { opmlFile in
      Text(opmlFile.title)
      Button("Cancel") { opmlViewModel.opmlFile = nil }
      List(Array(opmlFile.entries.values), id: \.feedURL) { entry in
        Text(entry.text)
      }
      .interactiveDismissDisabled(true)
    }
  }
}

#Preview {
  SettingsView().environment(Navigation())
}
