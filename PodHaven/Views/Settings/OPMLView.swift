// Copyright Justin Bishop, 2025

import SwiftUI

struct OPMLView: View {
  @State private var viewModel = OPMLViewModel()

  var body: some View {
    Form {
      Section("Import") {
        Button("Import OPML") {
          #if targetEnvironment(simulator)
          viewModel.importOPMLFileInSimulator("large")
          #else
          viewModel.opmlImporting = true
          #endif
        }
      }

      Section("Export") {
        Button("Export OPML") {
          viewModel.exportOPML()
        }
      }
    }
    .navigationTitle("OPML")
    .fileImporter(
      isPresented: $viewModel.opmlImporting,
      allowedContentTypes: [OPMLDocument.utType],
      onCompletion: { result in
        viewModel.opmlFileImporterCompletion(result)
      }
    )
    .sheet(item: $viewModel.opmlFile) { opmlFile in
      OPMLImportSheet(viewModel: viewModel, opmlFile: opmlFile)
    }
    .fileExporter(
      isPresented: $viewModel.opmlExporting,
      document: viewModel.exportDocument,
      contentType: OPMLDocument.utType,
      defaultFilename: "PodHaven Subscriptions"
    ) { result in
      switch result {
      case .success:
        break  // Success handled automatically
      case .failure:
        break  // TODO: Alert error
      }
    }
  }
}

#if DEBUG
#Preview {
  OPMLView()
    .preview()
}
#endif
