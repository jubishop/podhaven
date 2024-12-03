// Copyright Justin Bishop, 2024

import OPML
import SwiftUI

struct OPMLImportSheet: View {
  @Environment(Navigation.self) var navigation

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

    if opmlFile.inProgressCount > 0 {
      Text(
        """
        Importing \(opmlFile.totalCount) items; \
        \(opmlFile.inProgressCount) remaining
        """
      )
    } else {
      Text("\(opmlFile.successCount) new podcasts added")
    }
    if let opmlFile = opmlViewModel.opmlFile {
      ProgressView(
        totalAmount: Double(opmlFile.totalCount),
        colorAmounts: [
          .green: Double(opmlFile.successCount),
          .red: Double(opmlFile.failCount),
        ]
      )
      .frame(height: 40)
      .padding()
    }
    List {
      OPMLImportSheetSection(outlines: Array(opmlFile.downloading.values))
      OPMLImportSheetSection(outlines: Array(opmlFile.waiting.values))
      OPMLImportSheetSection(outlines: Array(opmlFile.failed))
      OPMLImportSheetSection(outlines: Array(opmlFile.finished.values))
      OPMLImportSheetSection(
        outlines: Array(opmlFile.alreadySubscribed.values)
      )
    }
    .animation(.default, value: Array(opmlFile.downloading.values))
    .animation(.default, value: Array(opmlFile.waiting.values))
    .animation(.default, value: Array(opmlFile.failed))
    .animation(.default, value: Array(opmlFile.finished.values))
    .animation(.default, value: Array(opmlFile.alreadySubscribed.values))
    .interactiveDismissDisabled(true)
  }
}

#Preview {
  @Previewable @State var opmlViewModel = OPMLViewModel()

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
