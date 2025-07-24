// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import Semaphore
import SwiftUI
import UniformTypeIdentifiers

final class OPMLDocument: FileDocument {
  static var utType: UTType {
    guard let utType = UTType(filenameExtension: "opml", conformingTo: .xml)
    else { Assert.fatal("Couldn't initialize opml UTType?") }

    return utType
  }

  static let readableContentTypes: [UTType] = []
  static let writableContentTypes: [UTType] = [utType]

  private let data: Data

  init(data: Data) {
    self.data = data
  }

  required init(configuration: ReadConfiguration) throws {
    data = Data()
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

@Observable @MainActor class OPMLOutline: Hashable, Identifiable {
  enum Status {
    case failed, waiting, downloading, finished
  }

  let id = UUID()
  var status: Status
  var feedURL: FeedURL
  var text: String

  convenience init(status: Status, text: String) {
    self.init(
      status: status,
      feedURL: FeedURL(URL.placeholder),
      text: text
    )
  }

  init(status: Status, feedURL: FeedURL, text: String) {
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

@Observable @MainActor class OPMLFile: Identifiable {
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

@Observable @MainActor class OPMLViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.feedManager) private var feedManager
  @ObservationIgnored @DynamicInjected(\.navigation) private var navigation
  @ObservationIgnored @DynamicInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.SettingsView.opml)

  var opmlImporting = false
  var opmlExporting = false

  var opmlFile: OPMLFile?
  var exportDocument: OPMLDocument?

  private var downloadSemaphor = AsyncSemaphore(value: 1)

  init() {}

  func opmlFileImporterCompletion(_ result: Result<URL, any Error>) {
    Task { [weak self] in
      guard let self else { return }
      do {
        switch result {
        case .success(let url):
          guard url.startAccessingSecurityScopedResource()
          else { throw PermissionError.securityScopedResourceDenied }

          let opml = try await PodcastOPML.parse(url)
          try await downloadOPMLFile(opml)
          url.stopAccessingSecurityScopedResource()
        case .failure(let error):
          throw error
        }
      } catch {
        alert("Couldn't import OPML file")
      }
    }
  }

  func stopDownloading() {
    Task { [weak self] in
      guard let self else { return }
      await feedManager.cancelAll()
      opmlFile = nil
    }
  }

  func finishedDownloading() {
    stopDownloading()
    navigation.currentTab = .podcasts
  }

  func exportOPML() {
    Task { [weak self] in
      guard let self else { return }
      do {
        let data = try await PodcastOPML.exportSubscribedPodcasts()
        exportDocument = OPMLDocument(data: data)
        opmlExporting = true
      } catch {
        Self.log.error(error)
        alert(ErrorKit.message(for: error))
      }
    }
  }

  // MARK: - Private Helpers

  private func downloadOPMLFile(_ opml: PodcastOPML) async throws {
    try await downloadSemaphor.waitUnlessCancelled()
    defer { downloadSemaphor.signal() }

    let opmlFile = OPMLFile(title: opml.head.title ?? "Podcast Subscriptions")
    let allPodcasts = IdentifiedArray(uniqueElements: try await repo.allPodcasts(), id: \.feedURL)

    for outline in opml.body.outlines {
      guard let feedURL = try? FeedURL(outline.xmlUrl.rawValue.convertToValidURL())
      else {
        opmlFile.failed.insert(OPMLOutline(status: .failed, text: outline.text))
        continue
      }

      if let podcast = allPodcasts[id: feedURL] {
        if !podcast.subscribed {
          Task { [weak self] in
            guard let self else { return }
            do {
              try await repo.markSubscribed(podcast.id)
              if let podcastSeries = try await repo.podcastSeries(podcast.id) {
                try await refreshManager.refreshSeries(podcastSeries: podcastSeries)
              }
            } catch {
              Self.log.error(error)
            }
          }
        }
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
        group.addTask { [weak self] in
          guard let self = self else { return }
          let feedTask = await self.feedManager.addURL(outline.feedURL)
          await feedTask.downloadBegan()
          await self.updateOutlineStatus(outline, in: opmlFile, to: .downloading)

          do {
            let podcastFeed = try await feedTask.feedParsed()
            let unsavedPodcast = try podcastFeed.toUnsavedPodcast(
              subscriptionDate: Date(),
              lastUpdate: Date()
            )

            await Task { @MainActor in
              outline.feedURL = unsavedPodcast.feedURL
              outline.text = unsavedPodcast.title
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
    await Task {
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
        Assert.fatal("Updated status back to waiting?!")
      }
    }
    .value
  }

  // MARK: - Simulator Methods

  #if DEBUG
  public func importOPMLFileInSimulator(_ resource: String) {
    let url = Bundle.main.url(
      forResource: resource,
      withExtension: "opml"
    )!
    Task { [weak self] in
      guard let self else { return }
      let opml = try await PodcastOPML.parse(url)
      try await downloadOPMLFile(opml)
    }
  }
  #endif
}
