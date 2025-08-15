// Copyright Justin Bishop, 2025

import SwiftUI

struct OPMLImportSheet: View {
  private let viewModel: OPMLViewModel
  private let opmlFile: OPMLFile

  init(viewModel: OPMLViewModel, opmlFile: OPMLFile) {
    self.viewModel = viewModel
    self.opmlFile = opmlFile
  }

  var body: some View {
    Text(opmlFile.title)
      .font(.headline)
      .padding([.top])

    HStack {
      Group {
        if opmlFile.inProgressCount == 0 {
          Button("Lets Go") {
            viewModel.finishedDownloading()
          }
        } else {
          Button(opmlFile.finished.count > 0 ? "Stop" : "Cancel") {
            viewModel.stopDownloading()
          }
        }
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

#if DEBUG
func importOPMLFile(_ viewModel: OPMLViewModel, _ resource: String) {
  Task {
    let url = Bundle.main.url(
      forResource: resource,
      withExtension: "opml"
    )!
    await viewModel.importOPMLFromURL(url: url)
  }
}

#Preview {
  @Previewable @State var viewModel = OPMLViewModel()

  Form {
    Button("Import Large") {
      importOPMLFile(viewModel, "large")
    }
    Button("Import Small") {
      importOPMLFile(viewModel, "small")
    }
    Button("Import Invalid") {
      importOPMLFile(viewModel, "invalid")
    }
    Button("Import Empty") {
      importOPMLFile(viewModel, "empty")
    }
  }
  .preview()
  .sheet(item: $viewModel.opmlFile) { opmlFile in
    OPMLImportSheet(viewModel: viewModel, opmlFile: opmlFile)
  }
}
#endif
