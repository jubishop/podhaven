// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import UIKit

extension Container {
  var cacheManagerSession: Factory<DataFetchable> {
    Factory(self) {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.allowsCellularAccess = true
      configuration.waitsForConnectivity = true
      configuration.timeoutIntervalForRequest = Double(30)
      configuration.timeoutIntervalForResource = Double(120)
      return URLSession(configuration: configuration)
    }
    .scope(.cached)
  }

  var cacheDownloadManager: Factory<DownloadManager> {
    Factory(self) {
      DownloadManager(session: self.cacheManagerSession(), maxConcurrentDownloads: 8)
    }
    .scope(.cached)
  }

  var cacheManager: Factory<CacheManager> {
    Factory(self) { CacheManager(downloadManager: self.cacheDownloadManager()) }.scope(.cached)
  }
}

actor CacheManager {
  @DynamicInjected(\.imageFetcher) private var imageFetcher
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sleeper) private var sleeper

  private var alert: Alert { get async { await Container.shared.alert() } }
  private var cacheState: CacheState { get async { await Container.shared.cacheState() } }
  private var playState: PlayState { get async { await Container.shared.playState() } }

  private static let log = Log.as(LogSubsystem.Cache.cacheManager)

  // MARK: - State Management

  private let downloadManager: DownloadManager
  private var currentQueuedEpisodeIDs: Set<Episode.ID> = []

  // MARK: - Initialization

  fileprivate init(downloadManager: DownloadManager) {
    self.downloadManager = downloadManager
  }

  func start() async throws {
    Self.log.debug("start: executing")

    try await Container.shared.podFileManager()
      .createDirectory(
        at: Self.cacheDirectory,
        withIntermediateDirectories: true
      )
    startMonitoringQueue()
  }

  // MARK: - Public Methods

  @discardableResult
  func downloadAndCache(_ podcastEpisode: PodcastEpisode) async throws(CacheError) -> Bool {
    Self.log.trace("downloadAndCache: \(podcastEpisode.toString)")

    guard podcastEpisode.episode.cachedFilename == nil
    else {
      Self.log.trace("downloadAndCache: \(podcastEpisode.toString) already cached")
      return false
    }

    let downloadTask = await downloadManager.addURL(podcastEpisode.episode.media.rawValue)

    if await cacheState.isDownloading(podcastEpisode.id) {
      Self.log.trace("downloadAndCache: \(podcastEpisode.toString) is already downloading")
      return false
    }

    let backgroundTask = await BackgroundTask.start(
      withName: "CacheManager.downloadAndCache: \(podcastEpisode.toString)"
    )
    await cacheState.setDownloadTask(podcastEpisode.id, downloadTask: downloadTask)
    defer {
      Task {
        await cacheState.removeDownloadTask(podcastEpisode.id)
        await backgroundTask.end()
      }
    }

    return try await CacheError.catch {
      await imageFetcher.prefetch([podcastEpisode.image])

      let downloadData = try await CacheError.mapError(
        { try await downloadTask.downloadFinished() },
        { CacheError.failedToDownload(podcastEpisode: podcastEpisode, caught: $0) }
      )

      let fileName = await generateCacheFilename(for: podcastEpisode.episode)
      let cacheURL = Self.resolveCachedFilepath(for: fileName)
      try await Container.shared.podFileManager().writeData(downloadData.data, to: cacheURL)
      try await repo.updateCachedFilename(podcastEpisode.id, fileName)

      Self.log.debug("downloadAndCache: successfully cached \(podcastEpisode.toString)")
      return true
    }
  }

  @discardableResult
  func downloadAndCache(_ episodeID: Episode.ID) async throws(CacheError) -> Bool {
    Self.log.trace("downloadAndCache: \(episodeID)")

    return try await CacheError.catch {
      let podcastEpisode = try await repo.podcastEpisode(episodeID)
      guard let podcastEpisode
      else { throw CacheError.episodeNotFound(episodeID) }

      return try await downloadAndCache(podcastEpisode)
    }
  }

  func clearCache(for episode: Episode) async throws(CacheError) -> Bool {
    Self.log.trace("clearCache: \(episode.toString)")

    guard !episode.queued
    else {
      Self.log.trace("clearCache: still queued, keeping cache for: \(episode.toString)")
      return false
    }

    if let onDeck = await playState.onDeck, onDeck == episode {
      Self.log.trace("clearCache: currently playing, keeping cache for: \(episode.toString)")
      return false
    }

    guard let cachedFilename = episode.cachedFilename
    else {
      Self.log.trace("clearCache: episode: \(episode.toString) has no cached filename")
      return false
    }

    do {
      let cacheURL = Self.resolveCachedFilepath(for: cachedFilename)
      try await Container.shared.podFileManager().removeItem(at: cacheURL)
    } catch {
      Self.log.error(error)
    }

    _ = try await CacheError.catch {
      try await repo.updateCachedFilename(episode.id, nil)
    }

    Self.log.debug("clearCache: cache cleared for: \(episode.toString)")
    return true
  }

  @discardableResult
  func clearCache(for episodeID: Episode.ID) async throws(CacheError) -> Bool {
    Self.log.debug("clearCache: \(episodeID)")

    return try await CacheError.catch {
      let episode: Episode? = try await repo.episode(episodeID)
      guard let episode
      else { throw CacheError.episodeNotFound(episodeID) }

      return try await clearCache(for: episode)
    }
  }

  // MARK: - Private Helpers

  private func startMonitoringQueue() {
    Assert.neverCalled()

    Self.log.debug("startMonitoringQueue: starting")

    Task(priority: .utility) { [weak self] in
      guard let self else { return }

      do {
        for try await queuedEpisodes in await observatory.queuedPodcastEpisodes() {
          Task { [weak self] in
            guard let self else { return }
            await handleQueueChange(queuedEpisodes)
          }
          try await sleeper.sleep(for: Duration.milliseconds(250))
        }
      } catch {
        Self.log.error(error)
        await alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  private func handleQueueChange(_ queuedEpisodes: [PodcastEpisode]) async {
    let queuedEpisodeIDs = Set(queuedEpisodes.map(\.id))
    let removedEpisodeIDs = currentQueuedEpisodeIDs.subtracting(queuedEpisodeIDs)
    currentQueuedEpisodeIDs = queuedEpisodeIDs

    Self.log.debug(
      """
      handleQueueChange:
        current queue: 
          \(queuedEpisodes.map(\.toString).joined(separator: "\n    "))
        removed: 
          \(removedEpisodeIDs)
      """
    )

    await withDiscardingTaskGroup { group in
      for podcastEpisode in queuedEpisodes {
        group.addTask { [weak self] in
          guard let self else { return }
          do {
            try await downloadAndCache(podcastEpisode)
          } catch {
            Self.log.error(error)
          }
        }
      }

      // Clear cache for removed episodes
      for episodeID in removedEpisodeIDs {
        group.addTask { [weak self] in
          guard let self else { return }
          do {
            try await cancelDownloadTaskOrClearCache(for: episodeID)
          } catch {
            Self.log.error(error)
          }
        }
      }
    }
  }

  private func cancelDownloadTaskOrClearCache(for episodeID: Episode.ID) async throws(CacheError) {
    if let downloadTask = await cacheState.getDownloadTask(episodeID) {
      Self.log.debug("Cancelling cache download task for episode \(episodeID)")

      await cacheState.removeDownloadTask(episodeID)
      await downloadTask.cancel()
    } else {
      try await clearCache(for: episodeID)
    }
  }

  private func generateCacheFilename(for episode: Episode) -> String {
    let mediaURL = episode.media.rawValue
    let fileExtension =
      mediaURL.pathExtension.isEmpty == false
      ? mediaURL.pathExtension
      : "mp3"
    return "\(mediaURL.hash(to: 12)).\(fileExtension)"
  }

  // MARK: - Static Helpers

  static func resolveCachedFilepath(for fileName: String) -> URL {
    Assert.precondition(!fileName.isEmpty, "Empty fileName in resolveCachedFilepath?")

    return cacheDirectory.appendingPathComponent(fileName)
  }

  private static var cacheDirectory: URL {
    AppInfo.applicationSupportDirectory.appendingPathComponent("episodes")
  }
}
