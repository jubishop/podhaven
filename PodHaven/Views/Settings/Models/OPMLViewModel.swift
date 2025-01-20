// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
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
  @ObservationIgnored @LazyInjected(\.repo) private var repo
  @ObservationIgnored @LazyInjected(\.feedManager) private var feedManager

  let opmlType: UTType

  var opmlImporting = false
  var opmlFile: OPMLFile?

  private var downloadSemaphor = AsyncSemaphore(value: 1)

  init() {
    guard let opmlType = UTType(filenameExtension: "opml", conformingTo: .xml)
    else { fatalError("Couldn't initialize opml UTType?") }
    self.opmlType = opmlType
  }

  func opmlFileImporterCompletion(_ result: Result<URL, any Error>) async throws {
    switch result {
    case .success(let url):
      guard url.startAccessingSecurityScopedResource()
      else { throw Err.msg("Couldn't start accessing security scoped response") }
      let opml = try await PodcastOPML.parse(url)
      try await downloadOPMLFile(opml)
      url.stopAccessingSecurityScopedResource()
    case .failure(let error):
      throw error
    }
  }

  func stopDownloading() async {
    await feedManager.cancelAll()
    opmlFile = nil
  }

  func finishedDownloading() async {
    await stopDownloading()
    Navigation.shared.showTab(.podcasts)
  }

  // MARK: - Private Methods

  private func downloadOPMLFile(_ opml: PodcastOPML) async throws {
    await downloadSemaphor.wait()
    defer { downloadSemaphor.signal() }

    let opmlFile = OPMLFile(title: opml.head.title ?? "Podcast Subscriptions")

    let allPodcasts = try await repo.allPodcasts()

    for outline in opml.body.outlines {
      guard let feedURL = try? outline.xmlUrl.convertToValidURL()
      else {
        opmlFile.failed.insert(OPMLOutline(status: .failed, text: outline.text))
        continue
      }

      if allPodcasts[id: feedURL] != nil {
        opmlFile.finished.insert(OPMLOutline(status: .finished, text: outline.text))
      } else {
        opmlFile.waiting.insert(
          OPMLOutline(
            status: .waiting,
            feedURL: feedURL,
            text: outline.text
          )
        )
      }
    }

    self.opmlFile = opmlFile
    await withDiscardingTaskGroup { group in
      for outline in opmlFile.waiting {
        group.addTask {
          let feedTask = await self.feedManager.addURL(outline.feedURL)
          await feedTask.downloadBegan()
          await self.updateOutlineStatus(outline, in: opmlFile, to: .downloading)

          do {
            guard case .success(let podcastFeed) = await feedTask.feedParsed()
            else { throw Err.msg("Failed to parse: \(await outline.text)") }
            let unsavedPodcast = try podcastFeed.toUnsavedPodcast()

            await Task { @MainActor in
              outline.feedURL = unsavedPodcast.feedURL
              outline.text = unsavedPodcast.toString
            }
            .value

            try await self.repo.insertSeries(
              unsavedPodcast,
              unsavedEpisodes: podcastFeed.episodes.compactMap { try? $0.toUnsavedEpisode() }
            )
            await self.updateOutlineStatus(outline, in: opmlFile, to: .finished)
          } catch DatabaseError.SQLITE_CONSTRAINT_UNIQUE {
            await self.updateOutlineStatus(outline, in: opmlFile, to: .finished)
          } catch {
            await self.updateOutlineStatus(outline, in: opmlFile, to: .failed)
          }
        }
      }
    }
  }

  private func updateOutlineStatus(
    _ outline: OPMLOutline,
    in opmlFile: OPMLFile,
    to newStatus: OPMLOutline.Status
  ) async {
    await Task { @MainActor in
      outline.status = newStatus
      switch newStatus {
      case .finished:
        opmlFile.downloading.remove(outline)
        opmlFile.finished.insert(outline)
      case .failed:
        opmlFile.downloading.remove(outline)
        opmlFile.failed.insert(outline)
      case .downloading:
        opmlFile.waiting.remove(outline)
        opmlFile.downloading.insert(outline)
      case .waiting:
        fatalError("Updated status back to waiting?!")
      }
    }
    .value
  }

  // MARK: - Simulator Methods

  #if DEBUG
    public func importOPMLFileInSimulator(_ resource: String) async throws {
      let url = Bundle.main.url(
        forResource: resource,
        withExtension: "opml"
      )!
      let opml = try await PodcastOPML.parse(url)
      try await downloadOPMLFile(opml)
    }
  #endif
}
