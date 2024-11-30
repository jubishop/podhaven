// Copyright Justin Bishop, 2024

import Foundation
import OPML
import UniformTypeIdentifiers

@Observable @MainActor final class OPMLViewModel {
  struct OPMLData: Identifiable {
    let id = UUID()
    let title: String
    let entries: [URL: OPMLEntry]
  }

  nonisolated let opmlDownloader: DownloadManager
  let opmlType = UTType(filenameExtension: "opml", conformingTo: .xml)!
  var opmlImporting = false
  var opmlData: OPMLData?

  init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.allowsCellularAccess = true
    configuration.waitsForConnectivity = true
    opmlDownloader = DownloadManager(
      session: URLSession(configuration: configuration)
    )
  }

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
      if let opmlData = opmlData {
        Task {
          var downloadTasks: [DownloadTask] = []
          for (feedURL, entry) in opmlData.entries {
            downloadTasks.append(await opmlDownloader.addURL(feedURL))
          }
          for downloadTask in downloadTasks {
            Task {
              let result = await downloadTask.downloadFinished()
              print(result)
            }
          }
        }
      }
    } catch {
      Failure.fatal("Couldn't parse OPML file: \(error)")
    }
  }
}
