// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import SwiftUI
import UniformTypeIdentifiers

extension Container {
  @MainActor var opmlViewModel: Factory<OPMLViewModel> {
    Factory(self) { @MainActor in OPMLViewModel() }.scope(.shared)
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
  @ObservationIgnored @DynamicInjected(\.feedManager) private var feedManager
  @ObservationIgnored @DynamicInjected(\.navigation) private var navigation
  @ObservationIgnored @DynamicInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.SettingsView.opml)

  var opmlImporting = false

  var opmlFile: OPMLFile?

  init() {}

  func opmlFileImporterCompletion(_ result: Result<URL, any Error>) {
    let url: URL
    do {
      url = try result.get()
    } catch {
      Self.log.error(error)
      guard ErrorKit.isRemarkable(error) else { return }
      alert(ErrorKit.coreMessage(for: error))
      return
    }

    Task { [weak self, url] in
      guard let self else { return }
      await importOPMLFromURL(url: url)
    }
  }

  func importOPMLFromURL(url: URL) async {
    do {
      Self.log.debug("Starting OPML import from URL: \(url)")

      _ = url.startAccessingSecurityScopedResource()
      let opml = try await PodcastOPML.parse(url)
      url.stopAccessingSecurityScopedResource()

      try await downloadOPMLFile(opml)
    } catch {
      Self.log.error(error)
      guard ErrorKit.isRemarkable(error) else { return }
      alert(ErrorKit.coreMessage(for: error))
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
    navigation.showPodcastList(.subscribed)
  }

  // MARK: - Private Helpers

  private func downloadOPMLFile(_ opml: PodcastOPML) async throws {
    let opmlFile = OPMLFile(title: opml.title ?? "Podcast Subscriptions")
    let allPodcasts = IdentifiedArray(uniqueElements: try await repo.allPodcasts(), id: \.feedURL)

    await withDiscardingTaskGroup { group in
      for rssFeed in opml.rssFeeds {
        if let podcast = allPodcasts[id: rssFeed.feedURL] {
          if !podcast.subscribed {
            group.addTask { [weak self, podcast] in
              guard let self else { return }
              do {
                try await repo.markSubscribed(podcast.id)
                if let podcastSeries = try await repo.podcastSeries(podcast.id) {
                  try await refreshManager.refreshSeries(podcastSeries: podcastSeries)
                }
              } catch {
                await Self.log.error(error)
              }
            }
          }
          opmlFile.finished.insert(OPMLOutline(status: .finished, text: rssFeed.title))
        } else {
          opmlFile.waiting.insert(
            OPMLOutline(
              status: .waiting,
              feedURL: rssFeed.feedURL,
              text: rssFeed.title
            )
          )
        }
      }

      self.opmlFile = opmlFile
      for outline in opmlFile.waiting {
        group.addTask { [weak self, opmlFile, outline] in
          guard let self = self else { return }

          let feedTask = await self.feedManager.addURL(outline.feedURL)
          await feedTask.downloadBegan()
          await updateOutlineStatus(outline, in: opmlFile, to: .downloading)

          do {
            let podcastFeed = try await feedTask.feedParsed()
            let unsavedPodcast = try podcastFeed.toUnsavedPodcast(
              subscriptionDate: Date(),
              lastUpdate: Date()
            )

            await Task { @MainActor [outline, unsavedPodcast] in
              outline.feedURL = unsavedPodcast.feedURL
              outline.text = unsavedPodcast.title
            }
            .value

            try await self.repo.insertSeries(
              unsavedPodcast,
              unsavedEpisodes: podcastFeed.episodes.compactMap { try? $0.toUnsavedEpisode() }
            )
            await updateOutlineStatus(outline, in: opmlFile, to: .finished)
          } catch DatabaseError.SQLITE_CONSTRAINT_UNIQUE {
            await updateOutlineStatus(outline, in: opmlFile, to: .finished)
          } catch {
            await updateOutlineStatus(outline, in: opmlFile, to: .failed)
          }
        }
      }
    }
  }

  private func updateOutlineStatus(
    _ outline: OPMLOutline,
    in opmlFile: OPMLFile,
    to newStatus: OPMLOutline.Status
  ) {
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
}
