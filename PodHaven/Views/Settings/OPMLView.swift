// Copyright Justin Bishop, 2024

import SwiftUI

struct OPMLView: View {
  @State private var opmlViewModel = OPMLViewModel()

  var body: some View {
    Form {
      Button(
        action: {
          #if targetEnvironment(simulator)
            opmlViewModel.importOPMLFileInSimulator("large")
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
      OPMLImportSheet(opmlViewModel: $opmlViewModel, opmlFile: opmlFile)
    }
  }
}

#Preview {
  OPMLView().forPreview()
}
