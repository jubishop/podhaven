// Copyright Justin Bishop, 2024

import SwiftUI

struct OPMLView: View {
  @State private var viewModel = OPMLViewModel()

  var body: some View {
    Form {
      Button(
        action: {
          #if targetEnvironment(simulator)
            Task { await viewModel.importOPMLFileInSimulator("large") }
          #else
            viewModel.opmlImporting = true
          #endif
        },
        label: { Text("Import OPML") }
      )

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
    .navigationTitle("OPML")
    .fileImporter(
      isPresented: $viewModel.opmlImporting,
      allowedContentTypes: [viewModel.opmlType],
      onCompletion: { result in
        Task { await viewModel.opmlFileImporterCompletion(result) }
      }
    )
    .sheet(item: $viewModel.opmlFile) { _ in
      OPMLImportSheet(viewModel: viewModel)
    }
  }
}

#Preview {
  Preview { OPMLView() }
}
