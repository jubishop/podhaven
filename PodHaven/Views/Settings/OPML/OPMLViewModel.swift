// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import OrderedCollections
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
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  nonisolated private static let log = Log.as(LogSubsystem.SettingsView.opml)

  private enum FeedOutcome {
    case finished
    case inLibrary
    case failed(remarkable: Bool)
    case cancelled
  }

  var opmlImporting = false
  var opmlFile: OPMLFile?

  private let downloadManager: DownloadManager

  fileprivate init() {
    downloadManager = DownloadManager(
      session: Container.shared.podcastFeedSession(),
      byteLimit: PodcastFeed.downloadByteLimit,
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

    let rssFeeds = opml.rssFeeds
    if rssFeeds.skippedCount > 0 {
      Self.log.info(
        "importOPMLFromURL: skipped \(rssFeeds.skippedCount) outlines without a usable feed URL"
      )
    }

    let opmlFile = OPMLFile(
      title: opml.title ?? "Podcast Subscriptions",
      skippedCount: rssFeeds.skippedCount
    )
    opmlFile.waiting = OrderedSet(
      rssFeeds.feeds.map { OPMLOutline(status: .waiting, feedURL: $0.feedURL, text: $0.title) }
    )
    self.opmlFile = opmlFile
  }

  func importFeeds() async {
    guard let opmlFile, opmlFile.phase == .reviewing else { return }
    opmlFile.phase = .importing

    do {
      try await downloadOPMLFile(opmlFile)
    } catch {
      Self.log.caughtError("importFeeds: failed to import feeds from '\(opmlFile.title)'", error)
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

  private func downloadOPMLFile(_ opmlFile: OPMLFile) async throws {
    let allPodcasts = IdentifiedArray(
      uniqueElements: try await repo.allPodcasts(AppDB.noOp),
      id: \.feedURL
    )

    var unsubscribedIDs: [Podcast.ID] = []
    var libraryOutlines: [OPMLOutline] = []
    var newOutlines: OrderedSet<OPMLOutline> = []
    for outline in opmlFile.waiting {
      if let podcast = allPodcasts[id: outline.feedURL] {
        if !podcast.subscribed { unsubscribedIDs.append(podcast.id) }
        libraryOutlines.append(outline)
      } else {
        newOutlines.append(outline)
      }
    }
    let resubscribedCount = try await repo.markSubscribed(unsubscribedIDs, level: .trace)

    for outline in libraryOutlines { outline.status = .finished }
    opmlFile.waiting = newOutlines
    opmlFile.finished.append(contentsOf: libraryOutlines)
    let newFeedCount = newOutlines.count
    Self.log.debug(
      """
      downloadOPMLFile: downloading \(newFeedCount) new feeds; \
      \(libraryOutlines.count) already in the library, \(resubscribedCount) resubscribed
      """
    )

    let counts = await withTaskGroup(of: FeedOutcome.self) { group in
      for outline in newOutlines {
        group.addTask { [weak self, opmlFile, outline] in
          guard let self = self else { return .cancelled }

          let downloadTask = await downloadManager.addURL(outline.feedURL.rawValue)

          do {
            try await downloadTask.downloadBegan()
            await updateOutlineStatus(outline, in: opmlFile, to: .downloading)
            let podcastFeed = try await PodcastFeed.parse(downloadTask.downloadFinished())
            let unsavedPodcast = try podcastFeed.toUnsavedPodcast(subscriptionDate: Date())

            await Task { @MainActor [outline, unsavedPodcast] in
              outline.feedURL = unsavedPodcast.feedURL
              outline.text = unsavedPodcast.title
            }
            .value

            do {
              try await repo.insertSeries(
                UnsavedPodcastSeries(
                  unsavedPodcast: unsavedPodcast,
                  unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
                ),
                level: .trace
              )
            } catch let error as DatabaseError
              where error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE
            {
              let libraryPodcasts = try await repo.allPodcasts(
                Podcast.Columns.feedURL == unsavedPodcast.feedURL
              )
              guard let libraryPodcast = libraryPodcasts.first else { throw error }
              if !libraryPodcast.subscribed {
                try await repo.markSubscribed(libraryPodcast.id, level: .trace)
              }
              await updateOutlineStatus(outline, in: opmlFile, to: .finished)
              return .inLibrary
            }
            await updateOutlineStatus(outline, in: opmlFile, to: .finished)
            return .finished
          } catch is CancellationError {
            await updateOutlineStatus(outline, in: opmlFile, to: .failed)
            return .cancelled
          } catch {
            Self.log.caughtError(
              """
              downloadOPMLFile: \
              failed to download/parse feed '\(await outline.text)' (\(await outline.feedURL))
              """,
              error,
              level: .notice
            )
            await updateOutlineStatus(outline, in: opmlFile, to: .failed)
            return .failed(remarkable: ErrorKit.isRemarkable(error))
          }
        }
      }

      var counts = (new: newFeedCount, inLibrary: 0, failed: 0, remarkable: 0, cancelled: 0)
      for await outcome in group {
        switch outcome {
        case .finished:
          break
        case .inLibrary:
          counts.inLibrary += 1
        case .failed(let remarkable):
          counts.failed += 1
          if remarkable { counts.remarkable += 1 }
        case .cancelled:
          counts.cancelled += 1
        }
      }
      return counts
    }

    Self.log.info(
      """
      downloadOPMLFile: imported \
      \(counts.new - counts.inLibrary - counts.failed - counts.cancelled) \
      of \(counts.new) new feeds; \(counts.inLibrary) resolved to library podcasts, \
      \(counts.failed) failed, \(counts.cancelled) cancelled
      """
    )
    guard counts.remarkable > 0 else { return }
    Self.log.warning(
      "downloadOPMLFile: \(counts.remarkable) of \(counts.new) new feeds failed to download or parse"
    )
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
      opmlFile.finished.append(outline)
    case .failed:
      opmlFile.downloading.remove(outline)
      opmlFile.failed.append(outline)
    case .downloading:
      opmlFile.waiting.remove(outline)
      opmlFile.downloading.append(outline)
    case .waiting:
      Assert.fatal("Updated status back to waiting?!")
    }
  }
}
