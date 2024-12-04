// Copyright Justin Bishop, 2024

import OPML
import SwiftUI

struct OPMLImportSheet: View {
  @Binding var viewModel: OPMLViewModel
  let opmlFile: OPMLFile

  init(viewModel: Binding<OPMLViewModel>) {
    guard let opmlFile = viewModel.wrappedValue.opmlFile else {
      fatalError("OPMLImportSheet must be initialized with an OPMLFile.")
    }
    self._viewModel = viewModel
    self.opmlFile = opmlFile
  }

  var body: some View {
    Text(opmlFile.title).font(.title)
    Group {
      Button(
        opmlFile.inProgressCount == 0
          ? "All Finished" : opmlFile.successCount > 0 ? "Stop" : "Cancel"
      ) {
        viewModel.stopDownloading()
      }
    }
    .buttonStyle(.bordered)
    .padding()

    Group {
      if opmlFile.inProgressCount > 0 {
        Text(
          """
          Importing \(opmlFile.totalCount) items; \
          \(opmlFile.inProgressCount) remaining
          """
        )
      } else {
        Text(
          """
          \(opmlFile.finished.count) podcasts added; \
          \(opmlFile.alreadySubscribed.count) already subscribed
          """
        )
      }
    }
    .padding()

    if let opmlFile = viewModel.opmlFile {
      ProgressView(
        totalAmount: Double(opmlFile.totalCount),
        colorAmounts: [
          .green: Double(opmlFile.successCount),
          .red: Double(opmlFile.failed.count),
        ]
      )
      .frame(height: 40)
      .padding()
    }

    let outlines = [
      Array(opmlFile.downloading.values),
      Array(opmlFile.waiting.values),
      opmlFile.failed,
      Array(opmlFile.finished.values),
      Array(opmlFile.alreadySubscribed.values),
    ]
    List {
      ForEach(outlines, id: \.self) { outlines in
        OPMLImportSheetSection(outlines: outlines)
      }
    }
    .animation(.default, value: outlines)
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
      OPMLImportSheet(viewModel: $viewModel)
    }
  }
}
