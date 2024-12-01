// Copyright Justin Bishop, 2024

import SwiftUI

struct OPMLView: View {
  @Environment(Navigation.self) var navigation

  @State private var opmlViewModel = OPMLViewModel()

  var body: some View {
    Form {
      Button(
        action: {
          #if targetEnvironment(simulator)
            let url = Bundle.main.url(
              forResource: "podcasts",
              withExtension: "opml"
            )!
            if let opml = opmlViewModel.importOPMLFile(url) {
              opmlViewModel.downloadOPMLFileInSimulator(opml)
            }
          #else
            opmlViewModel.opmlImporting = true
          #endif
        },
        label: { Text("Import OPML") }
      )
    }
    .navigationTitle("OPML")
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
          navigation.currentTab = .podcasts
        }
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
            switch outline.result {
              case .failure, .none:
                Image(systemName: "x.circle")
                  .foregroundColor(.red)
              case .success:
                Image(systemName: "checkmark.circle")
                  .foregroundColor(.green)
            }
          }
        }
      }
      .interactiveDismissDisabled(true)
    }
  }
}

#Preview {
  OPMLView().environment(Navigation())
}
