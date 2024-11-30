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
                if let opml = opmlViewModel.importOPMLFile(url) {
                  opmlViewModel.loadOPMLFileInSimulator(opml)
                }
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
      if opmlFile.outlines.values.allSatisfy({ $0.status == .finished }) {
        Button("All Finished") {
          opmlViewModel.opmlFile = nil
          navigation.currentTab = .upNext }
      } else {
        Button("Cancel") { opmlViewModel.opmlFile = nil }
      }
      List(Array(opmlFile.outlines.values)) { outline in
        HStack {
          Text(outline.text)
          Spacer()
          if outline.status == .waiting {
            Image(systemName: "clock")
              .foregroundColor(.gray)
          } else if outline.status == .downloading {
            Image(systemName: "arrow.down.circle")
              .foregroundColor(.blue)
          } else if outline.status == .finished {
            Image(systemName: "checkmark.circle")
              .foregroundColor(.green)
          }
        }
      }
      .interactiveDismissDisabled(true)
    }
  }
}

#Preview {
  SettingsView().environment(Navigation())
}
