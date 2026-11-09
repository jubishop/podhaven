// Copyright Justin Bishop, 2025

import FactoryKit
import OrderedCollections
import SwiftUI

struct OPMLImportSheet: View {
  private let viewModel: OPMLViewModel
  private let opmlFile: OPMLFile

  init(viewModel: OPMLViewModel, opmlFile: OPMLFile) {
    self.viewModel = viewModel
    self.opmlFile = opmlFile
  }

  var body: some View {
    Text(opmlFile.title)
      .font(.headline)
      .padding([.top])

    if opmlFile.skippedCount > 0 {
      Text(
        """
        Skipped \(opmlFile.skippedCount) \(opmlFile.skippedCount == 1 ? "entry" : "entries") \
        without a usable feed URL
        """
      )
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .padding([.horizontal])
    }

    switch opmlFile.phase {
    case .reviewing:
      Text(
        """
        Importing subscribes you to \(opmlFile.waiting.count) \
        \(opmlFile.waiting.count == 1 ? "podcast" : "podcasts") from this list.
        """
      )
      .font(.subheadline)
      .multilineTextAlignment(.center)
      .padding([.horizontal])

      HStack {
        Button("Cancel") {
          viewModel.stopDownloading()
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)

        Button("Import") {
          Task { await viewModel.importFeeds() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(opmlFile.waiting.isEmpty)
        .frame(maxWidth: .infinity)
      }
      .padding([.horizontal])

    case .importing:
      HStack {
        Group {
          if opmlFile.inProgressCount == 0 {
            Button("Lets Go") {
              viewModel.finishedDownloading()
            }
          } else {
            Button(opmlFile.finished.count > 0 ? "Stop" : "Cancel") {
              viewModel.stopDownloading()
            }
          }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)

        CircularProgressView(
          totalAmount: Double(opmlFile.totalCount),
          colorAmounts: [
            .green: Double(opmlFile.finished.count),
            .blue: Double(opmlFile.downloading.count),
            .red: Double(opmlFile.failed.count),
          ]
        )
        .frame(maxWidth: .infinity)
      }
      .padding([.horizontal])
    }

    List {
      OPMLImportSheetSection(outlines: opmlFile.downloading.elements)
      OPMLImportSheetSection(outlines: opmlFile.waiting.elements)
      OPMLImportSheetSection(outlines: opmlFile.failed.elements)
      OPMLImportSheetSection(outlines: opmlFile.finished.elements)
    }
    .interactiveDismissDisabled(true)
  }
}

#if DEBUG
func importOPMLFile(_ viewModel: OPMLViewModel, _ resource: String) {
  Task { [viewModel, resource] in
    guard
      let url = Bundle.main.url(
        forResource: resource,
        withExtension: "opml"
      )
    else { return }
    await viewModel.importOPMLFromURL(url: url)
  }
}

#Preview {
  @Previewable @State var viewModel = Container.shared.opmlViewModel()

  Form {
    Button("Import Large") {
      importOPMLFile(viewModel, "large")
    }
    Button("Import Small") {
      importOPMLFile(viewModel, "small")
    }
    Button("Import Invalid") {
      importOPMLFile(viewModel, "invalid")
    }
    Button("Import Empty") {
      importOPMLFile(viewModel, "empty")
    }
  }
  .preview()
  .sheet(item: $viewModel.opmlFile) { opmlFile in
    OPMLImportSheet(viewModel: viewModel, opmlFile: opmlFile)
  }
}

#Preview("Review") {
  @Previewable @State var opmlFile: OPMLFile? = {
    let opmlFile = OPMLFile(title: "Podcast Subscriptions", skippedCount: 2)
    opmlFile.waiting = [
      OPMLOutline(status: .waiting, text: "Hard Fork"),
      OPMLOutline(status: .waiting, text: "Lenny's Podcast"),
    ]
    return opmlFile
  }()

  Form {}
    .preview()
    .sheet(item: $opmlFile) { opmlFile in
      OPMLImportSheet(viewModel: Container.shared.opmlViewModel(), opmlFile: opmlFile)
    }
}

#Preview("Skipped entries") {
  @Previewable @State var opmlFile: OPMLFile? = {
    let opmlFile = OPMLFile(title: "Podcast Subscriptions", skippedCount: 3)
    opmlFile.phase = .importing
    opmlFile.finished = [OPMLOutline(status: .finished, text: "Hard Fork")]
    opmlFile.failed = [OPMLOutline(status: .failed, text: "Unreachable Podcast")]
    return opmlFile
  }()

  Form {}
    .preview()
    .sheet(item: $opmlFile) { opmlFile in
      OPMLImportSheet(viewModel: Container.shared.opmlViewModel(), opmlFile: opmlFile)
    }
}

#Preview("No usable feeds") {
  @Previewable @State var opmlFile: OPMLFile? = OPMLFile(
    title: "Podcast Subscriptions",
    skippedCount: 1
  )

  Form {}
    .preview()
    .sheet(item: $opmlFile) { opmlFile in
      OPMLImportSheet(viewModel: Container.shared.opmlViewModel(), opmlFile: opmlFile)
    }
}
#endif
