// Copyright Justin Bishop, 2024

import Foundation
import OPML
import UniformTypeIdentifiers

@Observable @MainActor final class SettingsViewModel {
  // MARK: - OPML

  let opmlType = UTType(filenameExtension: "opml", conformingTo: .xml)!
  var opmlImporting = false

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
      for entry in opml.entries {
        print(entry.feedURL!.absoluteString)
      }
    } catch {
      Failure.fatal("Couldn't parse OPML file: \(error)")
    }
  }
}
