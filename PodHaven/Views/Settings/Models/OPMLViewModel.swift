// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import OPML
import Semaphore
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
  let opmlType: UTType

  var opmlImporting = false
  var opmlFile: OPMLFile?

  private var downloadSemaphor = AsyncSemaphore(value: 1)
  private var feedManager: FeedManager?

  init() {
    guard let opmlType = UTType(filenameExtension: "opml", conformingTo: .xml)
    else { fatalError("Couldn't initialize opml UTType?") }
    self.opmlType = opmlType
  }

  func opmlFileImporterCompletion(_ result: Result<URL, any Error>) async {
    switch result {
    case .success(let url):
      if url.startAccessingSecurityScopedResource() {
        if let opml = await importOPMLFile(url) {
          await downloadOPMLFile(opml)
        }
      } else {
        Alert.shared("Couldn't start accessing security scoped response")
      }
      url.stopAccessingSecurityScopedResource()
    case .failure(let error):
      Alert.shared("Couldn't import OPML file: \(error)")
    }
  }

  func importOPMLFile(_ url: URL) async -> OPML? {
    await withCheckedContinuation { continuation in
      do {
        let opml = try OPML(file: url)

        if opml.entries.isEmpty {
          Alert.shared("OPML file has no subscriptions")
          continuation.resume(returning: nil)
        } else {
          continuation.resume(returning: opml)
        }
      } catch {
        Alert.shared("Couldn't parse OPML file", error: error)
        continuation.resume(returning: nil)
      }
    }
  }

  func stopDownloading() async {
    if let feedManager = self.feedManager {
      await feedManager.cancelAll()
    }
    self.feedManager = nil
    opmlFile = nil
  }

  func finishedDownloading() async {
    await stopDownloading()
    Navigation.shared.showTab(.podcasts)
  }

  // MARK: - Private Methods

  private func downloadOPMLFile(_ opml: OPML) async {
    await downloadSemaphor.wait()
    defer { downloadSemaphor.signal() }

    let opmlFile = OPMLFile(title: opml.title ?? "Podcast Subscriptions")

    let allPodcasts: PodcastArray
    do {
      allPodcasts = try await Repo.shared.allPodcasts()
    } catch {
      Alert.shared("Could not fetch podcasts for deduping", error: error)
      return
    }

    for entry in opml.entries {
      guard let feedURL = entry.feedURL,
        let feedURL = try? feedURL.convertToValidURL()
      else {
        opmlFile.failed.insert(OPMLOutline(status: .failed, text: entry.text))
        continue
      }

      if allPodcasts[id: feedURL] != nil {
        opmlFile.finished.insert(
          OPMLOutline(status: .finished, text: entry.text)
        )
        continue
      }

      opmlFile.waiting.insert(
        OPMLOutline(
          status: .waiting,
          feedURL: feedURL,
          text: entry.text
        )
      )
    }

    let feedManager = FeedManager()
    self.feedManager = feedManager
    defer { self.feedManager = nil }

    self.opmlFile = opmlFile
    await withDiscardingTaskGroup { group in
      for outline in opmlFile.waiting {
        group.addTask {
          defer {
            Task { @MainActor in
              guard outline.status != .finished else { return }
              outline.status = .failed
              opmlFile.downloading.remove(outline)
              opmlFile.failed.insert(outline)
            }
          }

          let feedTask = await feedManager.addURL(outline.feedURL)
          await feedTask.downloadBegan()

          await Task { @MainActor in
            outline.status = .downloading
            opmlFile.waiting.remove(outline)
            opmlFile.downloading.insert(outline)
          }
          .value

          guard case .success(let feedData) = await feedTask.feedParsed()
          else { return }

          await Task { @MainActor in
            outline.feedURL = feedData.feed.feedURL ?? outline.feedURL
            outline.text = feedData.feed.title ?? outline.text
          }
          .value

          guard
            let unsavedPodcast = await feedData.feed.toUnsavedPodcast(
              oldFeedURL: outline.feedURL,
              oldTitle: outline.text
            ),
            (try? await Repo.shared.insertSeries(
              unsavedPodcast,
              unsavedEpisodes: feedData.feed.items.map {
                try $0.toUnsavedEpisode()
              }
            )) != nil
          else { return }

          await Task { @MainActor in
            outline.status = .finished
            opmlFile.downloading.remove(outline)
            opmlFile.finished.insert(outline)
          }
          .value
        }
      }
    }
  }

  // MARK: - Simulator Methods

  #if DEBUG
    public func importOPMLFileInSimulator(_ resource: String) async {
      let url = Bundle.main.url(
        forResource: resource,
        withExtension: "opml"
      )!
      if let opml = await importOPMLFile(url) {
        await downloadOPMLFile(opml)
      }
    }
  #endif
}
