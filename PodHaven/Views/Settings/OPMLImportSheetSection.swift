// Copyright Justin Bishop, 2025

import SwiftUI

struct OPMLImportSheetSection: View {
  @Environment(\.colorScheme) private var colorScheme

  private var headers: [OPMLOutline.Status: Text] {
    [
      .failed: Text("Failed").foregroundStyle(AppIcon.failed.color(for: colorScheme)).bold(),
      .waiting: Text("Waiting").foregroundStyle(AppIcon.waiting.color(for: colorScheme)).bold(),
      .downloading: Text("Downloading")
        .foregroundStyle(AppIcon.downloadEpisode.color(for: colorScheme)).bold(),
      .finished: Text("Finished").foregroundStyle(AppIcon.episodeFinished.color(for: colorScheme))
        .bold(),
    ]
  }

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
              AppIcon.failed.image
            case .waiting:
              AppIcon.waiting.image
            case .downloading:
              AppIcon.downloadEpisode.image
            case .finished:
              AppIcon.episodeFinished.image
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
