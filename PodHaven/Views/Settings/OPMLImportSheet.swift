// Copyright Justin Bishop, 2024

import OPML
import SwiftUI

struct OPMLImportSheet: View {
  @State private var navigation = Navigation.shared

  @Binding var opmlViewModel: OPMLViewModel
  let opmlFile: OPMLFile

  init(opmlViewModel: Binding<OPMLViewModel>, opmlFile: OPMLFile) {
    self._opmlViewModel = opmlViewModel
    self.opmlFile = opmlFile
  }

  var body: some View {
    Text(opmlFile.title).font(.title)
    Group {
      if opmlFile.inProgressCount == 0 {
        Button("All Finished") {
          opmlViewModel.opmlFile = nil
          navigation.currentTab = .podcasts
        }
      } else {
        Button(opmlFile.successCount > 0 ? "Stop" : "Cancel") {
          opmlViewModel.opmlFile = nil
          if opmlFile.successCount > 0 {
            navigation.currentTab = .podcasts
          }
        }
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

    if let opmlFile = opmlViewModel.opmlFile {
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
  @Previewable @State var opmlViewModel = OPMLViewModel(repository: .empty())

  Preview {
    Form {
      Button("Import Large") {
        opmlViewModel.importOPMLFileInSimulator("large")
      }
      Button("Import Small") {
        opmlViewModel.importOPMLFileInSimulator("small")
      }
      Button("Import Invalid") {
        opmlViewModel.importOPMLFileInSimulator("invalid")
      }
      Button("Import Empty") {
        opmlViewModel.importOPMLFileInSimulator("empty")
      }
    }
    .sheet(item: $opmlViewModel.opmlFile) { opmlFile in
      OPMLImportSheet(opmlViewModel: $opmlViewModel, opmlFile: opmlFile)
    }
  }
}
