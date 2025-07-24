// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct OPMLView: View {
  @DynamicInjected(\.alert) private var alert
  @InjectedObservable(\.opmlViewModel) private var viewModel

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
        alert("Failed to export subscriptions")
        break
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
