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
    if opmlFile.outlines.values.allSatisfy({ $0.status == .finished }) {
      Button("All Finished") {
        opmlViewModel.opmlFile = nil
        navigation.currentTab = .podcasts
      }
    } else {
      Button("Cancel") { opmlViewModel.opmlFile = nil }
    }
    List(Array(opmlFile.outlines.values)) { outline in
      HStack {
        Text(outline.text)
        Spacer()
        if outline.status == .waiting {
          Image(systemName: "clock")
            .foregroundColor(.gray)
        } else if outline.status == .downloading {
          Image(systemName: "arrow.down.circle")
            .foregroundColor(.blue)
        } else if outline.status == .finished {
          switch outline.result {
          case .failure, .none:
            Image(systemName: "x.circle")
              .foregroundColor(.red)
          case .success:
            Image(systemName: "checkmark.circle")
              .foregroundColor(.green)
          }
        }
      }
    }
    .interactiveDismissDisabled(true)
  }
}

#if targetEnvironment(simulator)
  struct OPMLImportSheetPreview: View {
    var body: some View {
      Text("Import Sheet")
    }
  }
#endif

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
