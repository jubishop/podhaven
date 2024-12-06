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
    Text("Importing : \(opmlFile.title)")
      .font(.headline)
      .padding([.top])

    HStack {
      HStack {
        Button(
          opmlFile.inProgressCount == 0
            ? "Lets Go" : opmlFile.successCount > 0 ? "Stop" : "Cancel"
        ) {
          viewModel.stopDownloading()
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
        Text("\(opmlFile.inProgressCount)")
          .font(.largeTitle)
          .frame(maxWidth: .infinity)
      }
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
      OPMLImportSheetSection(outlines: Array(opmlFile.downloading.values))
      OPMLImportSheetSection(outlines: Array(opmlFile.waiting.values))
      OPMLImportSheetSection(outlines: opmlFile.failed)
      OPMLImportSheetSection(outlines: Array(opmlFile.finished.values))
      OPMLImportSheetSection(outlines: Array(opmlFile.alreadySubscribed.values))
    }
    .animation(.default, value: Array(opmlFile.downloading.values))
    .animation(.default, value: Array(opmlFile.waiting.values))
    .animation(.default, value: opmlFile.failed)
    .animation(.default, value: Array(opmlFile.finished.values))
    .animation(.default, value: Array(opmlFile.alreadySubscribed.values))
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
