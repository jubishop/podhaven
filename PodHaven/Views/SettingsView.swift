// Copyright Justin Bishop, 2024

import SwiftUI

struct SettingsView: View {
  @Environment(Navigation.self) var navigation

  @State private var viewModel = SettingsViewModel()

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
                viewModel.importOPMLFile(url)
              #else
                viewModel.opmlImporting = true
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
      isPresented: $viewModel.opmlImporting,
      allowedContentTypes: [viewModel.opmlType],
      onCompletion: viewModel.opmlFileImporterCompletion
    )
  }
}

#Preview {
  SettingsView().environment(Navigation())
}
