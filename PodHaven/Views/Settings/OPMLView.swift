// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI
import UniformTypeIdentifiers

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
        ShareLink(
          item: PodcastOPML.ExportItem(),
          preview: SharePreview(
            "PodHaven Subscriptions",
            image: Image(systemName: "doc.text")
          )
        ) {
          Label("Export OPML", systemImage: "square.and.arrow.up")
        }
      }
    }
    .navigationTitle("OPML")
    .fileImporter(
      isPresented: $viewModel.opmlImporting,
      allowedContentTypes: [UTType(filenameExtension: "opml", conformingTo: .xml) ?? .xml],
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
