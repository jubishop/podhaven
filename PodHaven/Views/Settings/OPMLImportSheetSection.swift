// Copyright Justin Bishop, 2024

import SwiftUI

struct OPMLImportSheetSection: View {
  private let headers: [OPMLOutline.Status: Text] = [
    .failed: Text("Failed").foregroundStyle(.red).bold(),
    .waiting: Text("Waiting").foregroundStyle(.blue).bold(),
    .downloading: Text("Downloading").foregroundStyle(.blue).bold(),
    .finished: Text("Finished").foregroundStyle(.green).bold(),
    .alreadySubscribed: Text("Already Subscribed").foregroundStyle(.green)
      .bold(),
  ]

  let outlines: [OPMLOutline]
  let status: OPMLOutline.Status

  init(outlines: [OPMLOutline]) {
    self.outlines = outlines
    if let first = outlines.first {
      status = first.status
    } else {
      status = .finished
    }
  }

  var body: some View {
    if outlines.isEmpty {
      EmptyView()
    } else {
      Section(header: headers[status]) {
        ForEach(outlines) { outline in
          HStack {
            Text(outline.text)
            Spacer()
            switch status {
            case .failed:
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
    }
  }
}

#Preview {
  Preview {
    List {
      // Should display nothing...
      OPMLImportSheetSection(outlines: [])
      OPMLImportSheetSection(
        outlines: [OPMLOutline(text: "Failed", status: .failed)]
      )
      OPMLImportSheetSection(
        outlines: [OPMLOutline(text: "Finished", status: .finished)]
      )
      OPMLImportSheetSection(
        outlines: [OPMLOutline(text: "Downloading", status: .downloading)]
      )
      OPMLImportSheetSection(
        outlines: [OPMLOutline(text: "Waiting", status: .waiting)]
      )
      OPMLImportSheetSection(
        outlines: [
          OPMLOutline(
            text: "Already Subscribed",
            status: .alreadySubscribed
          )
        ]
      )
    }
  }
}
