// Copyright Justin Bishop, 2025

import SwiftUI

struct OPMLImportSheetSection: View {
  static let maxVisibleRows = 100

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

  private let outlines: ArraySlice<OPMLOutline>
  private let hiddenCount: Int
  private let status: OPMLOutline.Status

  init(outlines: [OPMLOutline]) {
    self.outlines = outlines.prefix(Self.maxVisibleRows)
    hiddenCount = outlines.count - self.outlines.count
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
      Section {
        ForEach(outlines) { outline in
          HStack {
            Text(outline.text)
            Spacer()
            switch status {
            case .failed:
              AppIcon.failed.label
                .labelStyle(.iconOnly)
            case .waiting:
              AppIcon.waiting.label
                .labelStyle(.iconOnly)
            case .downloading:
              AppIcon.downloadEpisode
                .label("Downloading")
                .labelStyle(.iconOnly)
            case .finished:
              AppIcon.episodeFinished.label
                .labelStyle(.iconOnly)
            }
          }
        }
      } header: {
        headers[status]
      } footer: {
        if hiddenCount > 0 {
          Text("\(hiddenCount) more")
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

#Preview("More outlines than visible rows") {
  List {
    OPMLImportSheetSection(
      outlines: (0..<OPMLImportSheetSection.maxVisibleRows + 25)
        .map { OPMLOutline(status: .waiting, text: "Podcast \($0)") }
    )
  }
  .preview()
}
#endif
