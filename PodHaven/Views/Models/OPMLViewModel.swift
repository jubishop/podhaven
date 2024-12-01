// Copyright Justin Bishop, 2024

import Foundation
import OPML
import UniformTypeIdentifiers

@Observable @MainActor final class OPMLViewModel {
  @Observable final class OPMLFile: Identifiable {
    var id: String { title }

    let title: String
    let outlines: [URL: OPMLOutline]

    init(title: String, outlines: [URL: OPMLOutline]) {
      self.title = title
      self.outlines = outlines
    }
  }

  @Observable final class OPMLOutline: Identifiable {
    var id: URL { feedURL }

    enum Status {
      case waiting, downloading, finished
    }

    let text: String
    let feedURL: URL
    var status: Status = .waiting
    var result: DownloadResult?

    init(text: String, feedURL: URL) {
      self.text = text
      self.feedURL = feedURL
    }
  }

  let opmlType = UTType(filenameExtension: "opml", conformingTo: .xml)!
  var opmlImporting = false
  var opmlFile: OPMLFile?

  func opmlFileImporterCompletion(_ result: Result<URL, any Error>) {
    switch result {
    case .success(let url):
      if url.startAccessingSecurityScopedResource() {
        if let opml = importOPMLFile(url) {
          downloadOPMLFile(opml)
        }
      } else {
        Failure.fatal("Couldn't start accessing security scoped response.")
      }
      url.stopAccessingSecurityScopedResource()
    case .failure(let error):
      Failure.fatal("Couldn't import OPML file: \(error)")
    }
  }

  func importOPMLFile(_ url: URL) -> OPML? {
    guard let opml = try? OPML(file: url) else {
      Failure.fatal("Couldn't parse OPML file")
      return nil
    }
    return opml
  }

  // MARK: - Private Methods

  #if targetEnvironment(simulator)
    public func downloadOPMLFileInSimulator(_ opml: OPML) {
      downloadOPMLFile(opml)
    }
  #endif
  private func downloadOPMLFile(_ opml: OPML) {
    var outlines = [URL: OPMLOutline](capacity: opml.entries.count)
    for entry in opml.entries {
      guard let feedURL = entry.feedURL,
        var components = URLComponents(
          url: feedURL,
          resolvingAgainstBaseURL: false
        )
      else { continue }
      components.scheme = "https"
      guard let url = components.url else { continue }
      outlines[url] = OPMLOutline(
        text: entry.text,
        feedURL: url
      )
    }
    opmlFile = OPMLFile(
      title: opml.title ?? "Podcast Subscriptions",
      outlines: outlines
    )
    guard let opmlFile = opmlFile else {
      fatalError("Couldn't create OPMLFile?!")
    }
    Task {
      let opmlDownloader = createDownloadManager()
      let downloadTasks = await opmlDownloader.addURLs(
        opmlFile.outlines.map { $0.key }
      )
      for downloadTask in downloadTasks {
        Task {
          guard let outline = opmlFile.outlines[downloadTask.url] else {
            fatalError("No OPMLOutline for url: \(downloadTask.url)?")
          }
          #if targetEnvironment(simulator)
            try await Task.sleep(for: .milliseconds(Int.random(in: 100...1000)))
          #endif
          await downloadTask.downloadBegan()
          outline.status = .downloading
          #if targetEnvironment(simulator)
            try await Task.sleep(for: .milliseconds(Int.random(in: 100...1000)))
          #endif
          let result = await downloadTask.downloadFinished()
          outline.result = result
          outline.status = .finished
          // TODO: Save result to Podcasts DB
        }
      }
    }
  }

  private func createDownloadManager() -> DownloadManager {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.allowsCellularAccess = true
    configuration.waitsForConnectivity = true
    configuration.timeoutIntervalForRequest = 5
    configuration.timeoutIntervalForResource = 20
    return DownloadManager(
      session: URLSession(configuration: configuration)
    )
  }
}
