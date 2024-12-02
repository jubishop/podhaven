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
      if opmlFile.waiting.isEmpty && opmlFile.downloading.isEmpty {
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
    Text("\(opmlFile.totalCount) items, \(opmlFile.inProgressCount) remaining")
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
      OPMLImportSheetSection(outlines: Array(opmlFile.failed.values))
      OPMLImportSheetSection(outlines: opmlFile.invalid)
      OPMLImportSheetSection(outlines: Array(opmlFile.finished.values))
      OPMLImportSheetSection(
        outlines: Array(opmlFile.alreadySubscribed.values)
      )
    }
    .animation(.default, value: Array(opmlFile.downloading.values))
    .animation(.default, value: Array(opmlFile.waiting.values))
    .animation(.default, value: Array(opmlFile.failed.values))
    .animation(.default, value: opmlFile.invalid)
    .animation(.default, value: Array(opmlFile.finished.values))
    .animation(.default, value: Array(opmlFile.alreadySubscribed.values))
    .interactiveDismissDisabled(true)
  }
}

#Preview {
  struct OPMLImportSheetPreview: View {
    @State private var alert = Alert.shared
    @State private var opmlViewModel = OPMLViewModel()

    var body: some View {
      Form {
        Button("Import Large") {
          #if targetEnvironment(simulator)
            opmlViewModel.importOPMLFileInSimulator("large")
          #endif
        }
        Button("Import Small") {
          #if targetEnvironment(simulator)
            opmlViewModel.importOPMLFileInSimulator("small")
          #endif
        }
        Button("Import Invalid") {
          #if targetEnvironment(simulator)
            opmlViewModel.importOPMLFileInSimulator("invalid")
          #endif
        }
        Button("Import Empty") {
          #if targetEnvironment(simulator)
            opmlViewModel.importOPMLFileInSimulator("empty")
          #endif
        }
      }
      .sheet(item: $opmlViewModel.opmlFile) { opmlFile in
        OPMLImportSheet(opmlViewModel: $opmlViewModel, opmlFile: opmlFile)
      }
      .customAlert($alert.config)
    }
  }
  return OPMLImportSheetPreview().environment(Navigation())
}
