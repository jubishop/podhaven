// Copyright Justin Bishop, 2025

import SwiftUI

struct OPMLView: View {
  @State private var viewModel = OPMLViewModel()

  var body: some View {
    Form {
      Button(
        action: {
          #if targetEnvironment(simulator)
            Task { try await viewModel.importOPMLFileInSimulator("large") }
          #else
            viewModel.opmlImporting = true
          #endif
        },
        label: { Text("Import OPML") }
      )
    }
    .navigationTitle("OPML")
    .fileImporter(
      isPresented: $viewModel.opmlImporting,
      allowedContentTypes: [viewModel.opmlType],
      onCompletion: { result in
        Task { try await viewModel.opmlFileImporterCompletion(result) }
      }
    )
    .sheet(item: $viewModel.opmlFile) { opmlFile in
      OPMLImportSheet(viewModel: viewModel, opmlFile: opmlFile)
    }
  }
}

#Preview {
  Preview { OPMLView() }
}
