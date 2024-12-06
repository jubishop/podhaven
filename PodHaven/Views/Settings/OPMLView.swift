// Copyright Justin Bishop, 2024

import SwiftUI

struct OPMLView: View {
  @State private var viewModel: OPMLViewModel

  init(repository: PodcastRepository = .shared) {
    _viewModel = State(initialValue: OPMLViewModel(repository: repository))
  }

  var body: some View {
    Form {
      Button(
        action: {
          #if targetEnvironment(simulator)
            viewModel.importOPMLFileInSimulator("large")
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
      onCompletion: viewModel.opmlFileImporterCompletion
    )
    .sheet(item: $viewModel.opmlFile) { opmlFile in
      OPMLImportSheet(viewModel: viewModel)
    }
  }
}

#Preview {
  Preview { OPMLView(repository: .empty()) }
}
