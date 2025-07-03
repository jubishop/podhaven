// Copyright Justin Bishop, 2025

import SwiftUI

struct OPMLView: View {
  @State private var viewModel = OPMLViewModel()

  var body: some View {
    Form {
      Button("Import OPML") {
        #if targetEnvironment(simulator)
        viewModel.importOPMLFileInSimulator("large")
        #else
        viewModel.opmlImporting = true
        #endif
      }
    }
    .navigationTitle("OPML")
    .fileImporter(
      isPresented: $viewModel.opmlImporting,
      allowedContentTypes: [viewModel.opmlType],
      onCompletion: { result in
        viewModel.opmlFileImporterCompletion(result)
      }
    )
    .sheet(item: $viewModel.opmlFile) { opmlFile in
      OPMLImportSheet(viewModel: viewModel, opmlFile: opmlFile)
    }
  }
}

#if DEBUG
#Preview {
  OPMLView()
    .preview()
}
#endif
