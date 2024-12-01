// Copyright Justin Bishop, 2024

import Foundation
import OPML
import SwiftUI
import UniformTypeIdentifiers

@Observable @MainActor final class OPMLFile: Identifiable {
  let id = UUID()
  let title: String
  let outlines: [URL: OPMLOutline]
  let invalidFeeds: [String]

  init(title: String, outlines: [URL: OPMLOutline], invalidFeeds: [String]) {
    self.title = title
    self.outlines = outlines
    self.invalidFeeds = invalidFeeds
  }
}

@Observable @MainActor final class OPMLOutline: Identifiable {
  enum Status {
    case invalidURL, alreadySubscribed, waiting, downloading, finished
  }

  let id = UUID()
  let text: String
  let feedURL: URL?
  var status: Status = .waiting
  var result: DownloadResult?

  init(text: String, feedURL: URL? = nil, status: Status) {
    self.text = text
    self.feedURL = feedURL
    self.status = status
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
    if opml.entries.isEmpty {
      Failure.fatal("OPML file has no subscriptions")
      return nil
    }
    return opml
  }

  // MARK: - Private Methods

  private func downloadOPMLFile(_ opml: OPML) {
    var invalidFeeds: [String] = []
    let outlines: [URL: OPMLOutline] = Dictionary(
      uniqueKeysWithValues: opml.entries.compactMap { entry in
        guard let feedURL = entry.feedURL,
          let url = try? UnsavedPodcast.convertToValidURL(feedURL)
        else {
          invalidFeeds.append(entry.text)
          return nil
        }
        return (
          url,
          OPMLOutline(text: entry.text, feedURL: url, status: .waiting)
        )
      }
    )
    opmlFile = OPMLFile(
      title: opml.title ?? "Podcast Subscriptions",
      outlines: outlines,
      invalidFeeds: invalidFeeds
    )
    guard let opmlFile = opmlFile else {
      fatalError("Couldn't create OPMLFile?!")
    }
    Task {
      let opmlDownloader = createDownloadManager()
      // TODO: Check if podcast already in DB before downloading it.
      let downloadTasks = await opmlDownloader.addURLs(
        opmlFile.outlines.map { $0.key }
      )
      for downloadTask in downloadTasks {
        Task {
          guard let outline = opmlFile.outlines[downloadTask.url] else {
            fatalError("No OPMLOutline for url: \(downloadTask.url)?")
          }
          #if targetEnvironment(simulator)
            try await Task.sleep(for: .milliseconds(Int.random(in: 300...3000)))
          #endif
          await downloadTask.downloadBegan()
          outline.status = .downloading
          #if targetEnvironment(simulator)
            try await Task.sleep(for: .milliseconds(Int.random(in: 300...3000)))
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
    let timeout = Double(15)
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout
    return DownloadManager(
      session: URLSession(configuration: configuration)
    )
  }

  // MARK: - Simulator Methods

  #if targetEnvironment(simulator)
    public func importOPMLFileInSimulator() {
      let url = Bundle.main.url(
        forResource: "podcasts",
        withExtension: "opml"
      )!
      if let opml = importOPMLFile(url) {
        downloadOPMLFile(opml)
      }
    }
  #endif
}
