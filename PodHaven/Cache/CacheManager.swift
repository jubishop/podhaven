// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB

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

  var cacheManager: Factory<CacheManager> {
    Factory(self) { CacheManager(session: self.cacheManagerSession()) }.scope(.cached)
  }
}

actor CacheManager {
  @DynamicInjected(\.notifications) private var notifications
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  private var alert: Alert { get async { await Container.shared.alert() } }

  private static let log = Log.as(LogSubsystem.Cache.cacheManager)

  // MARK: - State Management

  private let downloadManager: DownloadManager
  private var currentQueuedEpisodeIDs: Set<Episode.ID> = []
  private var activeDownloadTasks: [Episode.ID: DownloadTask] = [:]

  // MARK: - Initialization

  fileprivate init(session: DataFetchable) {
    downloadManager = DownloadManager(session: session, maxConcurrentDownloads: 4)
  }

  func start() async {
    Self.log.debug("start: executing")

    startMonitoringQueue()
  }

  // MARK: - Public Methods

  func downloadAndCacheEpisode(_ episode: Episode) async throws(CacheError) {
    Self.log.debug("downloadAndCacheEpisode: \(episode.toString)")

    guard episode.cachedMediaURL == nil
    else {
      Self.log.debug("downloadAndCacheEpisode: \(episode.toString) already cached")
      return
    }

    let downloadTask = await downloadManager.addURL(episode.media.rawValue)
    activeDownloadTasks[episode.id] = downloadTask
    defer { activeDownloadTasks.removeValue(forKey: episode.id) }

    let downloadData = try await CacheError.catch {
      try await downloadTask.downloadFinished()
    }

    let cacheURL = try await saveToCache(data: downloadData.data, for: episode)

    guard currentQueuedEpisodeIDs.contains(episode.id)
    else {
      Self.log.debug(
        "downloadAndCacheEpisode: episode \(episode.toString) no longer queued, cleaning up cache"
      )

      do {
        try FileManager.default.removeItem(at: cacheURL)
      } catch {
        Self.log.error(error)
      }
      return
    }

    _ = try await CacheError.catch {
      try await repo.updateCachedMediaURL(episode.id, cacheURL)
    }

    Self.log.debug("downloadAndCacheEpisode: cached to \(cacheURL)")
  }

  func clearCache(for episode: Episode) async throws(CacheError) {
    Self.log.debug("clearCache: \(episode.toString)")

    guard !episode.queued
    else {
      Self.log.debug("clearCache: still queued, keeping cache for: \(episode.toString)")
      return
    }

    if let cachedURL = episode.cachedMediaURL {
      do {
        try FileManager.default.removeItem(at: cachedURL)
      } catch {
        Self.log.error(error)
      }
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
    let newEpisodeIDs = Set(queuedEpisodes.map(\.id))
    let removedEpisodeIDs = currentQueuedEpisodeIDs.subtracting(newEpisodeIDs)
    let newEpisodes = queuedEpisodes.reversed().filter { $0.episode.cachedMediaURL == nil }

    Self.log.debug(
      """
      handleQueueChange:
        current queue: \(queuedEpisodes.count) episodes
        removed: \(removedEpisodeIDs.count) episodes
        new: \(newEpisodes.count) episodes
      """
    )

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

      // Cache new episodes in reverse order (most imminent first)
      for podcastEpisode in newEpisodes {
        group.addTask { [weak self] in
          guard let self else { return }
          do {
            try await downloadAndCacheEpisode(podcastEpisode.episode)
          } catch {
            Self.log.error(error)
          }
        }
      }
    }

    currentQueuedEpisodeIDs = newEpisodeIDs
  }

  private func cancelDownloadTaskOrClearCache(for episodeID: Episode.ID) async throws(CacheError) {
    if let downloadTask = activeDownloadTasks[episodeID] {
      Self.log.debug("Cancelling cache download task for episode \(episodeID)")

      await downloadTask.cancel()
      activeDownloadTasks.removeValue(forKey: episodeID)
    } else {
      try await clearCache(for: episodeID)
    }
  }

  private func saveToCache(data: Data, for episode: Episode) async throws(CacheError) -> URL {
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
      let documentsDirectory = FileManager.default
        .urls(
          for: .documentDirectory,
          in: .userDomainMask
        )
        .first
    else { throw CacheError.documentsDirectoryNotFound }

    let cacheDirectory = documentsDirectory.appendingPathComponent("EpisodeCache")

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
    "\(episode.media.rawValue.hashTo(12)).mp3"
  }
}
