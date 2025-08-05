// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import Semaphore

extension Container {
  var cacheManagerSession: Factory<DataFetchable> {
    Factory(self) {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.allowsCellularAccess = true
      configuration.waitsForConnectivity = true
      let timeout = Double(30)
      configuration.timeoutIntervalForRequest = timeout
      configuration.timeoutIntervalForResource = timeout
      return URLSession(configuration: configuration)
    }
    .scope(.cached)
  }

  var cacheDownloadManager: Factory<DownloadManager> {
    Factory(self) {
      DownloadManager(session: self.cacheManagerSession(), maxConcurrentDownloads: 4)
    }
    .scope(.cached)
  }

  var cacheManager: Factory<CacheManager> {
    Factory(self) { CacheManager(downloadManager: self.cacheDownloadManager()) }.scope(.cached)
  }
}

actor CacheManager {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.imageFetcher) private var imageFetcher

  private var alert: Alert { get async { await Container.shared.alert() } }
  private var playState: PlayState { get async { await Container.shared.playState() } }

  private static let log = Log.as(LogSubsystem.Cache.cacheManager)

  // MARK: - State Management

  private let downloadManager: DownloadManager
  private var currentQueuedEpisodeIDs: Set<Episode.ID> = []
  private var activeDownloadTasks: [Episode.ID: DownloadTask] = [:]

  // MARK: - Initialization

  fileprivate init(downloadManager: DownloadManager) {
    self.downloadManager = downloadManager
  }

  func start() async {
    Self.log.debug("start: executing")

    startMonitoringQueue()
  }

  // MARK: - Public Methods

  func downloadAndCache(_ podcastEpisode: PodcastEpisode) async throws(CacheError) {
    Self.log.debug("downloadAndCache: \(podcastEpisode.toString)")

    guard podcastEpisode.episode.cachedMediaURL == nil
    else {
      Self.log.debug("downloadAndCache: \(podcastEpisode.toString) already cached")
      return
    }

    await imageFetcher.prefetch([podcastEpisode.image])

    let downloadTask = await downloadManager.addURL(podcastEpisode.episode.media.rawValue)
    activeDownloadTasks[podcastEpisode.id] = downloadTask
    defer { activeDownloadTasks.removeValue(forKey: podcastEpisode.id) }

    let downloadData = try await CacheError.catch {
      try await downloadTask.downloadFinished()
    }
    let cacheURL = try await saveToCache(data: downloadData.data, for: podcastEpisode.episode)
    _ = try await CacheError.catch {
      try await repo.updateCachedMediaURL(podcastEpisode.id, cacheURL)
    }

    Self.log.debug("downloadAndCache: successfully cached \(podcastEpisode.toString)")
  }

  func clearCache(for episode: Episode) async throws(CacheError) {
    Self.log.debug("clearCache: \(episode.toString)")

    guard !episode.queued
    else {
      Self.log.debug("clearCache: still queued, keeping cache for: \(episode.toString)")
      return
    }

    if let onDeck = await playState.onDeck, onDeck == episode {
      Self.log.debug("clearCache: currently playing, keeping cache for: \(episode.toString)")
      return
    }

    guard let cachedURL = episode.cachedMediaURL
    else {
      Self.log.debug("Episode: \(episode.toString) has no cached media URL")
      return
    }

    do {
      try FileManager.default.removeItem(at: cachedURL)
    } catch {
      Self.log.error(error)
    }

    _ = try await CacheError.catch {
      try await repo.updateCachedMediaURL(episode.id, nil)
    }

    Self.log.debug("clearCache: cache cleared for: \(episode.toString)")
  }

  func clearCache(for episodeID: Episode.ID) async throws(CacheError) {
    Self.log.debug("clearCache: \(episodeID)")

    try await CacheError.catch {
      let episode: Episode? = try await repo.episode(episodeID)
      guard let episode
      else { throw CacheError.episodeNotFound(episodeID) }

      try await clearCache(for: episode)
    }
  }

  // MARK: - Private Helpers

  private func startMonitoringQueue() {
    Assert.neverCalled()

    Self.log.debug("startMonitoringQueue: starting")

    Task { [weak self] in
      guard let self else { return }

      do {
        for try await queuedEpisodes in await observatory.queuedPodcastEpisodes() {
          await handleQueueChange(queuedEpisodes)
        }
      } catch {
        Self.log.error(error)
        await alert(ErrorKit.message(for: error))
      }
    }
  }

  private func handleQueueChange(_ queuedEpisodes: [PodcastEpisode]) async {
    let queuedEpisodeIDs = Set(queuedEpisodes.map(\.id))
    let removedEpisodeIDs = currentQueuedEpisodeIDs.subtracting(queuedEpisodeIDs)
    let newEpisodes: [PodcastEpisode] = queuedEpisodes.filter {
      !currentQueuedEpisodeIDs.contains($0.id)
    }
    currentQueuedEpisodeIDs = queuedEpisodeIDs

    Self.log.debug(
      """
      handleQueueChange:
        current queue: \(queuedEpisodes.map(\.toString))
        removed: \(removedEpisodeIDs.count) episodes
        new: \(newEpisodes.count) episodes
      """
    )

    // Cache new episodes in reverse order (most imminent first)
    for podcastEpisode in newEpisodes.reversed() {
      let asyncSemaphore = AsyncSemaphore(value: 0)
      Task { [weak self] in
        guard let self else { return }
        do {
          asyncSemaphore.signal()
          try await downloadAndCache(podcastEpisode)
        } catch {
          Self.log.error(error)
        }
      }
      await asyncSemaphore.wait()
    }

    await withDiscardingTaskGroup { group in
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
    if let downloadTask = activeDownloadTasks[episodeID] {
      Self.log.debug("Cancelling cache download task for episode \(episodeID)")

      activeDownloadTasks.removeValue(forKey: episodeID)
      await downloadTask.cancel()
    } else {
      try await clearCache(for: episodeID)
    }
  }

  private func saveToCache(data: Data, for episode: Episode) async throws(CacheError) -> URL {
    Self.log.debug("saveToCache: \(episode.toString)")

    let cacheDirectory = try getCacheDirectory()
    let fileName = generateCacheFileName(for: episode)
    let fileURL = cacheDirectory.appendingPathComponent(fileName)

    try CacheError.catch {
      try data.write(to: fileURL)
    }
    return fileURL
  }

  private func getCacheDirectory() throws(CacheError) -> URL {
    guard
      let applicationSupportDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first
    else { throw CacheError.cachesDirectoryNotFound }
    let cacheDirectory = applicationSupportDirectory.appendingPathComponent("episodes")

    if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
      try CacheError.catch {
        try FileManager.default.createDirectory(
          at: cacheDirectory,
          withIntermediateDirectories: true,
          attributes: nil
        )
      }
    }

    return cacheDirectory
  }

  private func generateCacheFileName(for episode: Episode) -> String {
    let mediaURL = episode.media.rawValue
    let fileExtension =
      mediaURL.pathExtension.isEmpty == false
      ? mediaURL.pathExtension
      : "mp3"
    return "\(mediaURL.hash(to: 12)).\(fileExtension)"
  }
}
