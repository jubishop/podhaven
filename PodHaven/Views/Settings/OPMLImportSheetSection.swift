// Copyright Justin Bishop, 2025

import SwiftUI

struct OPMLImportSheetSection: View {
  private let headers: [OPMLOutline.Status: Text] = [
    .failed: Text("Failed").foregroundStyle(.red).bold(),
    .waiting: Text("Waiting").foregroundStyle(.gray).bold(),
    .downloading: Text("Downloading").foregroundStyle(.blue).bold(),
    .finished: Text("Finished").foregroundStyle(.green).bold(),
  ]

  private let outlines: [OPMLOutline]
  private let status: OPMLOutline.Status

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
              AppLabel.failed.image
                .foregroundColor(.red)
            case .waiting:
              AppLabel.waiting.image
                .foregroundColor(.gray)
            case .downloading:
              AppLabel.downloadEpisode.image
                .foregroundColor(.blue)
            case .finished:
              AppLabel.episodeFinished.image
                .foregroundColor(.green)
            }
          }
        }
      }
    }
  }
}

#if DEBUG
#Preview {
  List {
    // Should display nothing...
    OPMLImportSheetSection(outlines: [])
    OPMLImportSheetSection(
      outlines: [OPMLOutline(status: .failed, text: "Failed")]
    )
    OPMLImportSheetSection(
      outlines: [OPMLOutline(status: .finished, text: "Finished")]
    )
    OPMLImportSheetSection(
      outlines: [OPMLOutline(status: .downloading, text: "Downloading")]
    )
    OPMLImportSheetSection(
      outlines: [OPMLOutline(status: .waiting, text: "Waiting")]
    )
  }
  .preview()
}
#endif
