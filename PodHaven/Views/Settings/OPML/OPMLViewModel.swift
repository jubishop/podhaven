// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import SwiftUI
import Tagged
import UniformTypeIdentifiers

@Observable @MainActor class OPMLViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.navigation) private var navigation
  @ObservationIgnored @DynamicInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.SettingsView.opml)

  var opmlImporting = false
  var opmlFile: OPMLFile?

  private let downloadManager: DownloadManager

  init() {
    downloadManager = DownloadManager(session: Container.shared.podcastFeedSession())
  }

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
      uniqueElements: try await repo.allPodcasts(AppDB.NoOp),
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
          await downloadTask.downloadBegan()
          await updateOutlineStatus(outline, in: opmlFile, to: .downloading)

          do {
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
