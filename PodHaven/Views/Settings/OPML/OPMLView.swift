// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI
import UniformTypeIdentifiers

struct OPMLView: View {
  @DynamicInjected(\.alert) private var alert

  @State private var viewModel = OPMLViewModel()

  var body: some View {
    Form {
      Section("Import") {
        Button("Import OPML") {
          viewModel.opmlImporting = true
        }
      }

      Section("Export") {
        ShareLink(
          item: PodcastOPML.ExportItem(),
          preview: SharePreview(
            "PodHaven Subscriptions",
            image: Image("AppIconImage")
          ),
          label: { AppIcon.exportOPML.label }
        )
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
