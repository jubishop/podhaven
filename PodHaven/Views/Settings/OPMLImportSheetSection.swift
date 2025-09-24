// Copyright Justin Bishop, 2025

import SwiftUI

struct OPMLImportSheetSection: View {
  private let headers: [OPMLOutline.Status: Text] = [
    .failed: Text("Failed").foregroundStyle(AppLabel.failed.color).bold(),
    .waiting: Text("Waiting").foregroundStyle(AppLabel.waiting.color).bold(),
    .downloading: Text("Downloading").foregroundStyle(AppLabel.downloadEpisode.color).bold(),
    .finished: Text("Finished").foregroundStyle(AppLabel.episodeFinished.color).bold(),
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
              AppLabel.failed.coloredImage
            case .waiting:
              AppLabel.waiting.coloredImage
            case .downloading:
              AppLabel.downloadEpisode.coloredImage
            case .finished:
              AppLabel.episodeFinished.coloredImage
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
