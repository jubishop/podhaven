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
          ? "Lets Go" : opmlFile.finished.count > 0 ? "Stop" : "Cancel"
      ) {
        Task { await viewModel.stopDownloading() }
      }
      .buttonStyle(.bordered)
      .frame(maxWidth: .infinity)

      CircularProgressView(
        totalAmount: Double(opmlFile.totalCount),
        colorAmounts: [
          .green: Double(opmlFile.finished.count),
          .blue: Double(opmlFile.downloading.count),
          .red: Double(opmlFile.failed.count),
        ]
      )
      .frame(maxWidth: .infinity)
    }
    .padding([.horizontal])

    List {
      OPMLImportSheetSection(outlines: Array(opmlFile.downloading))
      OPMLImportSheetSection(outlines: Array(opmlFile.waiting))
      OPMLImportSheetSection(outlines: Array(opmlFile.failed))
      OPMLImportSheetSection(outlines: Array(opmlFile.finished))
    }
    .animation(.default, value: Array(opmlFile.downloading))
    .animation(.default, value: Array(opmlFile.waiting))
    .animation(.default, value: Array(opmlFile.failed))
    .animation(.default, value: Array(opmlFile.finished))
    .interactiveDismissDisabled(true)
  }
}

#Preview {
  @Previewable @State var viewModel = OPMLViewModel()

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

      #if DEBUG
        Section("Debugging") {
          Button("Clear DB") {
            Task {
              try AppDatabase.shared.db.write { db in
                try Podcast.deleteAll(db)
              }
            }
          }
        }
      #endif
    }
    .sheet(item: $viewModel.opmlFile) { opmlFile in
      OPMLImportSheet(viewModel: viewModel)
    }
  }
}
