// Copyright Justin Bishop, 2024

import Foundation
import OPML
import UniformTypeIdentifiers

@Observable @MainActor final class SettingsViewModel {
  // MARK: - OPML

  struct OPMLData: Identifiable {
    let id = UUID()
    let title: String
    let entries: Dictionary<URL, OPMLEntry>
  }

  let opmlType = UTType(filenameExtension: "opml", conformingTo: .xml)!
  var opmlImporting = false
  var opmlData: OPMLData?

  func opmlFileImporterCompletion(_ result: Result<URL, any Error>) {
    switch result {
    case .success(let url):
      if url.startAccessingSecurityScopedResource() {
        importOPMLFile(url)
      } else {
        Failure.fatal("Couldn't start accessing security scoped response.")
      }
      url.stopAccessingSecurityScopedResource()
    case .failure(let error):
      Failure.fatal("Couldn't import OPML file: \(error)")
    }
  }

  func importOPMLFile(_ url: URL) {
    do {
      let opml = try OPML(file: url)
      opmlData = OPMLData(
        title: opml.title ?? "Podcast Subscriptions",
        entries: Dictionary(
          uniqueKeysWithValues: opml.entries.compactMap { entry in
            guard let feedURL = entry.feedURL else { return nil }
            return (feedURL, entry)
          }
        )
      )
    } catch {
      Failure.fatal("Couldn't parse OPML file: \(error)")
    }
  }
}
