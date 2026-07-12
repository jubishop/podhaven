// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import SwiftUI
import Tagged
import UniformTypeIdentifiers

extension Container {
  @MainActor var opmlViewModel: Factory<OPMLViewModel> {
    Factory(self) { OPMLViewModel() }.scope(.cached)
  }
}

@Observable @MainActor class OPMLViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.navigation) private var navigation
  @ObservationIgnored @DynamicInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  nonisolated private static let log = Log.as(LogSubsystem.SettingsView.opml)

  var opmlImporting = false
  var opmlFile: OPMLFile?

  private let downloadManager: DownloadManager

  fileprivate init() {
    downloadManager = DownloadManager(
      session: Container.shared.podcastFeedSession(),
      maxConcurrentDownloads: 16
    )
  }

  func opmlFileImporterCompletion(_ result: Result<URL, any Error>) {
    let url: URL
    do {
      url = try result.get()
    } catch {
      Self.log.caughtError(
        "opmlFileImporterCompletion: failed to get URL from file importer",
        error
      )
      guard ErrorKit.isRemarkable(error) else { return }
      alert(ErrorKit.message(for: error))
      return
    }

    Task { [weak self, url] in
      guard let self else { return }
      await importOPMLFromURL(url: url)
    }
  }

  func importOPMLFromURL(url: URL) async {
    Self.log.debug("Starting OPML import from URL: \(url)")

    _ = url.startAccessingSecurityScopedResource()
    defer { url.stopAccessingSecurityScopedResource() }

    let opml: PodcastOPML
    do {
      opml = try await PodcastOPML.parse(url)
    } catch {
      Self.log.caughtError("importOPMLFromURL: failed to parse OPML at \(url)", error)
      guard ErrorKit.isRemarkable(error) else { return }
      alert(ErrorKit.message(for: error))
      return
    }

    do {
      try await downloadOPMLFile(opml)
    } catch {
      Self.log.caughtError("importOPMLFromURL: failed to download OPML feeds from \(url)", error)
      guard ErrorKit.isRemarkable(error) else { return }
      alert(ErrorKit.message(for: error))
    }
  }

  func stopDownloading() {
    Task { [weak self] in
      guard let self else { return }
      await downloadManager.cancelAllDownloads()
      opmlFile = nil
    }
  }

  func finishedDownloading() {
    stopDownloading()
    navigation.showPodcastList(.subscribed)
  }

  // MARK: - Private Helpers

  private func downloadOPMLFile(_ opml: PodcastOPML) async throws {
    Self.log.debug("Downloading podcasts in opml: \(opml)")

    let opmlFile = OPMLFile(title: opml.title ?? "Podcast Subscriptions")
    let allPodcasts = IdentifiedArray(
      uniqueElements: try await repo.allPodcasts(AppDB.noOp),
      id: \.feedURL
    )

    await withDiscardingTaskGroup { group in
      for rssFeed in opml.rssFeeds {
        if let podcast = allPodcasts[id: rssFeed.feedURL] {
          Self.log.debug("Podcast: \(podcast.toString) already exists")

          if !podcast.subscribed {
            group.addTask { [weak self, podcast] in
              guard let self else { return }
              do {
                try await repo.markSubscribed(podcast.id)
                if let podcast = try await repo.podcast(podcast.id) {
                  try await refreshManager.refreshSeries(podcast: podcast)
                }
              } catch {
                Self.log.caughtError(
                  "downloadOPML: subscribe/refresh failed \(podcast.toString)",
                  error
                )
              }
            }
          }
          opmlFile.finished.insert(OPMLOutline(status: .finished, text: rssFeed.title))
        } else {
          Self.log.debug("Marking as waiting to download: \(rssFeed.title)")

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

          let downloadTask = await downloadManager.addURL(outline.feedURL.rawValue)

          do {
            try await downloadTask.downloadBegan()
            await updateOutlineStatus(outline, in: opmlFile, to: .downloading)
            let podcastFeed = try await PodcastFeed.parse(downloadTask.downloadFinished())
            let unsavedPodcast = try podcastFeed.toUnsavedPodcast()

            await Task { @MainActor [outline, unsavedPodcast] in
              outline.feedURL = unsavedPodcast.feedURL
              outline.text = unsavedPodcast.title
            }
            .value

            let podcastSeries = try await repo.insertSeries(
              UnsavedPodcastSeries(
                unsavedPodcast: unsavedPodcast,
                unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
              )
            )
            try await repo.markSubscribed(podcastSeries.id)
            await updateOutlineStatus(outline, in: opmlFile, to: .finished)
          } catch DatabaseError.SQLITE_CONSTRAINT_UNIQUE {
            await updateOutlineStatus(outline, in: opmlFile, to: .finished)
          } catch {
            Self.log.caughtError(
              """
              downloadOPMLFile: \
              failed to download/parse feed '\(await outline.text)' (\(await outline.feedURL))
              """,
              error
            )
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
    Self.log.debug("Marking \(outline.text) to \(newStatus)")

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
