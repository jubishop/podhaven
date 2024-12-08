// Copyright Justin Bishop, 2024

import OPML
import SwiftUI

struct OPMLImportSheet: View {
  let viewModel: OPMLViewModel
  let opmlFile: OPMLFile

  init(viewModel: OPMLViewModel) {
    guard let opmlFile = viewModel.opmlFile else {
      fatalError("OPMLImportSheet must be initialized with an OPMLFile.")
    }
    self.viewModel = viewModel
    self.opmlFile = opmlFile
  }

  var body: some View {
    Text(String(opmlFile.title))
      .font(.headline)
      .padding([.top])

    HStack {
      Button(
        opmlFile.inProgressCount == 0
          ? "Lets Go" : opmlFile.successCount > 0 ? "Stop" : "Cancel"
      ) {
        viewModel.stopDownloading()
      }
      .buttonStyle(.bordered)
      .frame(maxWidth: .infinity)

      if let opmlFile = viewModel.opmlFile {
        CircularProgressView(
          totalAmount: Double(opmlFile.totalCount),
          colorAmounts: [
            .green: Double(opmlFile.successCount),
            .red: Double(opmlFile.failed.count),
          ]
        )
        .frame(maxWidth: .infinity)
      }
    }
    .padding([.horizontal])

    List {
      OPMLImportSheetSection(outlines: Array(opmlFile.downloading))
      OPMLImportSheetSection(outlines: Array(opmlFile.waiting))
      OPMLImportSheetSection(outlines: Array(opmlFile.failed))
      OPMLImportSheetSection(outlines: Array(opmlFile.finished))
      OPMLImportSheetSection(outlines: Array(opmlFile.alreadySubscribed))
    }
    .animation(.default, value: Array(opmlFile.downloading))
    .animation(.default, value: Array(opmlFile.waiting))
    .animation(.default, value: Array(opmlFile.failed))
    .animation(.default, value: Array(opmlFile.finished))
    .animation(.default, value: Array(opmlFile.alreadySubscribed))
    .interactiveDismissDisabled(true)
  }
}

#Preview {
  @Previewable @State var viewModel = OPMLViewModel(repository: .empty())

  Preview {
    Form {
      Button("Import Large") {
        viewModel.importOPMLFileInSimulator("large")
      }
      Button("Import Small") {
        viewModel.importOPMLFileInSimulator("small")
      }
      Button("Import Invalid") {
        viewModel.importOPMLFileInSimulator("invalid")
      }
      Button("Import Empty") {
        viewModel.importOPMLFileInSimulator("empty")
      }
    }
    .sheet(item: $viewModel.opmlFile) { opmlFile in
      OPMLImportSheet(viewModel: viewModel)
    }
  }
}
