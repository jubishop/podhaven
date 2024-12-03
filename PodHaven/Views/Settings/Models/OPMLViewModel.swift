// Copyright Justin Bishop, 2024

import Foundation
import OPML
import UniformTypeIdentifiers

@Observable @MainActor final class OPMLFile: Identifiable {
  let id = UUID()
  let title: String
  var totalCount: Int {
    invalid.count
      + alreadySubscribed.count
      + waiting.count
      + downloading.count
      + failed.count
      + finished.count
  }
  var inProgressCount: Int {
    waiting.count + downloading.count
  }
  var failCount: Int {
    invalid.count + failed.count
  }
  var successCount: Int {
    alreadySubscribed.count + finished.count
  }
  var invalid: [OPMLOutline] = []
  var alreadySubscribed: [URL: OPMLOutline] = [:]
  var waiting: [URL: OPMLOutline] = [:]
  var downloading: [URL: OPMLOutline] = [:]
  var failed: [URL: OPMLOutline] = [:]
  var finished: [URL: OPMLOutline] = [:]

  init(title: String) {
    self.title = title
  }
}

@Observable @MainActor final class OPMLOutline: Identifiable, Equatable {
  enum Status {
    case invalid, alreadySubscribed, waiting, downloading, failed, finished
  }

  let id = UUID()
  let text: String
  var status: Status
  let feedURL: URL?
  var result: DownloadResult?

  init(text: String, status: Status, feedURL: URL? = nil) {
    self.text = text
    self.status = status
    self.feedURL = feedURL
  }

  nonisolated static func == (lhs: OPMLOutline, rhs: OPMLOutline) -> Bool {
    lhs.id == rhs.id
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
        Alert.shared("Couldn't start accessing security scoped response.")
      }
      url.stopAccessingSecurityScopedResource()
    case .failure(let error):
      Alert.shared("Couldn't import OPML file: \(error)")
    }
  }

  func importOPMLFile(_ url: URL) -> OPML? {
    guard let opml = try? OPML(file: url) else {
      Alert.shared("Couldn't parse OPML file")
      return nil
    }
    if opml.entries.isEmpty {
      Alert.shared("OPML file has no subscriptions")
      return nil
    }
    return opml
  }

  // MARK: - Private Methods

  private func downloadOPMLFile(_ opml: OPML) {
    let opmlFile = OPMLFile(title: opml.title ?? "Podcast Subscriptions")
    for entry in opml.entries {
      guard let feedURL = entry.feedURL,
        let url = try? UnsavedPodcast.convertToValidURL(feedURL)
      else {
        opmlFile.invalid.append(OPMLOutline(text: entry.text, status: .invalid))
        continue
      }
      // TODO: Check if podcast already in DB before setting it as waiting
      opmlFile.waiting[url] = OPMLOutline(
        text: entry.text,
        status: .waiting,
        feedURL: url
      )
    }
    self.opmlFile = opmlFile
    Task {
      let opmlDownloader = createDownloadManager()
      let downloadTasks = await opmlDownloader.addURLs(
        opmlFile.waiting.map { $0.key }
      )
      for downloadTask in downloadTasks {
        Task {
          guard let outline = opmlFile.waiting[downloadTask.url] else {
            fatalError("No OPMLOutline for url: \(downloadTask.url)?")
          }
          #if DEBUG
            try await Task.sleep(for: .milliseconds(Int.random(in: 500...5000)))
          #endif
          await downloadTask.downloadBegan()
          outline.status = .downloading
          opmlFile.downloading[downloadTask.url] = outline
          opmlFile.waiting.removeValue(forKey: downloadTask.url)
          #if DEBUG
            try await Task.sleep(for: .milliseconds(Int.random(in: 500...5000)))
          #endif
          let result = await downloadTask.downloadFinished()
          switch result {
          case .success:
            outline.status = .finished
            opmlFile.finished[downloadTask.url] = outline
          case .failure:
            outline.status = .failed
            opmlFile.failed[downloadTask.url] = outline
          }
          opmlFile.downloading.removeValue(forKey: downloadTask.url)
          outline.result = result

          // TODO: Parse, then Save result to Podcasts DB
          // if case .success(let data) = result {
          // }
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

  #if DEBUG
    public func importOPMLFileInSimulator(_ resource: String) {
      let url = Bundle.main.url(
        forResource: resource,
        withExtension: "opml"
      )!
      if let opml = importOPMLFile(url) {
        downloadOPMLFile(opml)
      }
    }
  #endif
}
