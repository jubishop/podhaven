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
    Text(opmlFile.title)
    if opmlFile.waiting.isEmpty && opmlFile.downloading.isEmpty {
      Button("All Finished") {
        opmlViewModel.opmlFile = nil
        navigation.currentTab = .podcasts
      }
    } else {
      Button("Cancel") { opmlViewModel.opmlFile = nil }
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
    @State private var opmlViewModel: OPMLViewModel

    init() {
      _opmlViewModel = State(initialValue: OPMLViewModel())
      #if targetEnvironment(simulator)
        opmlViewModel.importOPMLFileInSimulator()
      #endif
    }

    var body: some View {
      Form {}
        .sheet(item: $opmlViewModel.opmlFile) { opmlFile in
          OPMLImportSheet(opmlViewModel: $opmlViewModel, opmlFile: opmlFile)
        }
    }
  }
  return OPMLImportSheetPreview().environment(Navigation())
}
