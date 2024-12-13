// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import OPML
import UniformTypeIdentifiers

@Observable @MainActor
final class OPMLOutline: Equatable, Hashable, Identifiable {
  enum Status {
    case failed, waiting, downloading, finished
  }

  let id = UUID()
  var status: Status
  var feedURL: URL
  var text: String

  convenience init(status: Status, text: String) {
    self.init(
      status: status,
      feedURL: URL.placeholder,
      text: text
    )
  }

  init(status: Status, feedURL: URL, text: String) {
    self.status = status
    self.feedURL = feedURL
    self.text = text
  }

  nonisolated static func == (lhs: OPMLOutline, rhs: OPMLOutline) -> Bool {
    lhs.id == rhs.id
  }

  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

@Observable @MainActor final class OPMLFile: Identifiable {
  let id = UUID()
  let title: String
  var totalCount: Int {
    failed.count
      + waiting.count
      + downloading.count
      + finished.count
  }
  var inProgressCount: Int {
    waiting.count + downloading.count
  }
  var failed: Set<OPMLOutline> = []
  var waiting: Set<OPMLOutline> = []
  var downloading: Set<OPMLOutline> = []
  var finished: Set<OPMLOutline> = []

  init(title: String) {
    self.title = title
  }
}

@Observable @MainActor final class OPMLViewModel {
  private var downloadManager: DownloadManager?
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
        Alert.shared("Couldn't start accessing security scoped response")
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

  func stopDownloading() async {
    if let downloadManager = downloadManager {
      await downloadManager.cancelAllDownloads()
    }
    opmlFile = nil
    Navigation.shared.currentTab = .podcasts
  }

  // MARK: - Private Methods

  private func downloadOPMLFile(_ opml: OPML) {
    let opmlFile = OPMLFile(title: opml.title ?? "Podcast Subscriptions")
    for entry in opml.entries {
      guard let feedURL = entry.feedURL,
        let validURL = try? feedURL.convertToValidURL()
      else {
        opmlFile.failed.insert(OPMLOutline(status: .failed, text: entry.text))
        continue
      }
      opmlFile.waiting.insert(
        OPMLOutline(
          status: .waiting,
          feedURL: validURL,
          text: entry.text
        )
      )
    }

    self.opmlFile = opmlFile
    for outline in opmlFile.waiting {
      Task.detached {
        defer {
          Task { @MainActor in
            guard outline.status != .finished else { return }
            outline.status = .failed
            opmlFile.downloading.remove(outline)
            opmlFile.failed.insert(outline)
          }
        }

        let feedTask = await FeedManager.shared.addURL(outline.feedURL)

        await feedTask.downloadBegan()
        await Task { @MainActor in
          outline.status = .downloading
          opmlFile.waiting.remove(outline)
          opmlFile.downloading.insert(outline)
        }
        .value

        guard case .success(let data) = await feedTask.feedParsed()
        else { return }

        await Task { @MainActor in
          outline.feedURL = data.feed.feedURL ?? outline.feedURL
          outline.text = data.feed.title ?? outline.text
        }
        .value

        guard
          let unsavedPodcast = await data.feed.toUnsavedPodcast(
            feedURL: outline.feedURL,
            oldTitle: outline.text
          ),
          (try? await PodcastRepository.shared.insertSeries(
            unsavedPodcast,
            unsavedEpisodes: data.feed.items.map { $0.toUnsavedEpisode() }
          )) != nil
        else { return }

        if let image = data.feed.image {
          PodcastImages.shared.prefetch([image])
        }

        await Task { @MainActor in
          outline.status = .finished
          opmlFile.downloading.remove(outline)
          opmlFile.finished.insert(outline)
        }
        .value
      }
    }
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
