// Copyright Justin Bishop, 2025

import FactoryKit
import Logging
import SwiftUI
import UniformTypeIdentifiers

struct OPMLView: View {
  nonisolated private static let log = Log.as(LogSubsystem.SettingsView.opml)

  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.opmlViewModel) private var viewModel

  var body: some View {
    @Bindable var viewModel = viewModel
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
      allowedContentTypes: [PodcastOPML.contentType, .xml],
      onCompletion: { result in
        viewModel.opmlFileImporterCompletion(result)
      }
    )
    .sheet(item: $viewModel.opmlFile) { opmlFile in
      OPMLImportSheet(viewModel: viewModel, opmlFile: opmlFile)
    }
    .onChange(of: viewModel.opmlFile?.id) { oldID, newID in
      switch (oldID, newID) {
      case (nil, .some(let id)):
        Self.log.debug(
          "OPML import sheet presented (id: \(id), title: \(viewModel.opmlFile?.title ?? "?"))"
        )
      case (.some(let id), nil):
        Self.log.debug("OPML import sheet dismissed (id: \(id))")
      case (.some(let oldID), .some(let newID)):
        Self.log.debug("OPML import sheet replaced (oldID: \(oldID), newID: \(newID))")
      case (nil, nil):
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
