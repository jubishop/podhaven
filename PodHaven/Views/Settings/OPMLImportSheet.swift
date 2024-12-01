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
      if !opmlFile.invalid.isEmpty {
        Section(header: Text("Invalid").foregroundStyle(.red).bold()) {
          ForEach(opmlFile.invalid) { outline in
            OPMLImportSheetListRow(outline: outline)
          }
        }
      }
      if !opmlFile.failed.isEmpty {
        Section(header: Text("Failed").foregroundStyle(.red).bold()) {
          ForEach(Array(opmlFile.failed.values)) { outline in
            OPMLImportSheetListRow(outline: outline)
          }
        }
      }
      if !opmlFile.finished.isEmpty {
        Section(header: Text("Finished").foregroundStyle(.green).bold()) {
          ForEach(Array(opmlFile.finished.values)) { outline in
            OPMLImportSheetListRow(outline: outline)
          }
        }
      }
      if !opmlFile.downloading.isEmpty {
        Section(header: Text("Downloading").foregroundStyle(.blue).bold()) {
          ForEach(Array(opmlFile.downloading.values)) { outline in
            OPMLImportSheetListRow(outline: outline)
          }
        }
      }
      if !opmlFile.waiting.isEmpty {
        Section(header: Text("Waiting").foregroundStyle(.blue).bold()) {
          ForEach(Array(opmlFile.waiting.values)) { outline in
            OPMLImportSheetListRow(outline: outline)
          }
        }
      }
      if !opmlFile.alreadySubscribed.isEmpty {
        Section(
          header: Text("Already Subscribed").foregroundStyle(.green).bold()
        ) {
          ForEach(Array(opmlFile.alreadySubscribed.values)) { outline in
            OPMLImportSheetListRow(outline: outline)
          }
        }
      }
    }
    .animation(.default, value: opmlFile.invalid)
    .animation(.default, value: Array(opmlFile.failed.values))
    .animation(.default, value: Array(opmlFile.finished.values))
    .animation(.default, value: Array(opmlFile.downloading.values))
    .animation(.default, value: Array(opmlFile.waiting.values))
    .animation(.default, value: Array(opmlFile.alreadySubscribed.values))
    .interactiveDismissDisabled(true)
  }
}

struct OPMLImportSheetListRow: View {
  let outline: OPMLOutline

  var body: some View {
    HStack {
      Text(outline.text)
      Spacer()
      switch outline.status {
      case .invalid, .failed:
        Image(systemName: "x.circle")
          .foregroundColor(.red)
      case .waiting:
        Image(systemName: "clock")
          .foregroundColor(.gray)
      case .downloading:
        Image(systemName: "arrow.down.circle")
          .foregroundColor(.blue)
      case .finished, .alreadySubscribed:
        Image(systemName: "checkmark.circle")
          .foregroundColor(.green)

      }
    }
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
