// Copyright Justin Bishop, 2024

import Foundation
import OPML
import UniformTypeIdentifiers

@Observable class OPMLFile: Identifiable {
  var id: String { title }
  let title: String
  let entries: [URL: OPMLOutline]

  init(title: String, entries: [URL: OPMLOutline]) {
    self.title = title
    self.entries = entries
  }
}

@Observable class OPMLOutline {
  let text: String
  let feedURL: URL

  init(text: String, feedURL: URL) {
    self.text = text
    self.feedURL = feedURL
  }
}

@Observable @MainActor final class OPMLViewModel {
  let opmlType = UTType(filenameExtension: "opml", conformingTo: .xml)!
  var opmlImporting = false
  var opmlFile: OPMLFile?

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
    guard let opml = try? OPML(file: url) else {
      return Failure.fatal("Couldn't parse OPML file")
    }
    var opmlEntries = [URL: OPMLOutline](capacity: opml.entries.count)
    for entry in opml.entries {
      guard let feedURL = entry.feedURL,
        var components = URLComponents(
          url: feedURL,
          resolvingAgainstBaseURL: false
        )
      else { continue }
      components.scheme = "https"
      guard let url = components.url else { continue }
      opmlEntries[url] = OPMLOutline(
        text: entry.text,
        feedURL: url
      )
    }
    opmlFile = OPMLFile(
      title: opml.title ?? "Podcast Subscriptions",
      entries: opmlEntries
    )
    guard let opmlFile = opmlFile else { return }
    Task {
      let opmlDownloader = createDownloadManager()
      var downloadTasks = [DownloadTask](capacity: opmlFile.entries.count)
      for (feedURL, _) in opmlFile.entries {
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

  // MARK: - Private Methods

  func createDownloadManager() -> DownloadManager {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.allowsCellularAccess = true
    configuration.waitsForConnectivity = true
    return DownloadManager(
      session: URLSession(configuration: configuration)
    )
  }
}
