// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import UIKit

extension Container {
  var cacheManagerSession: Factory<any DataFetchable> {
    Factory(self) {
      let config = URLSessionConfiguration.background(
        withIdentifier: AppInfo.bundleIdentifier + ".cache.bg"
      )
      config.sessionSendsLaunchEvents = true
      config.allowsCellularAccess = true
      config.waitsForConnectivity = true
      config.isDiscretionary = false
      config.httpMaximumConnectionsPerHost = 4
      return URLSession(
        configuration: config,
        delegate: self.cacheBackgroundDelegate(),
        delegateQueue: nil
      )
    }
    .scope(.cached)
  }

  var cacheManager: Factory<CacheManager> {
    Factory(self) { CacheManager() }.scope(.cached)
  }
}

actor CacheManager {
  @DynamicInjected(\.cacheManagerSession) private var cacheManagerSession
  @DynamicInjected(\.imageFetcher) private var imageFetcher
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sleeper) private var sleeper

  private var alert: Alert { get async { await Container.shared.alert() } }
  private var cacheState: CacheState { get async { await Container.shared.cacheState() } }
  private var playState: PlayState { get async { await Container.shared.playState() } }

  private static let log = Log.as(LogSubsystem.Cache.cacheManager)

  // MARK: - State Management

  private var currentQueuedEpisodeIDs: Set<Episode.ID> = []

  // MARK: - Initialization

  fileprivate init() {}

  func start() async throws {
    Self.log.debug("start: executing")

    try await Container.shared.podFileManager()
      .createDirectory(
        at: Self.cacheDirectory,
        withIntermediateDirectories: true
      )
    startMonitoringQueue()

    await adoptInFlightBackgroundDownloads()
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

    if await cacheState.isDownloading(podcastEpisode.id) {
      Self.log.trace("downloadAndCache: \(podcastEpisode.toString) is already downloading")
      return false
    }

    // Delegate to injected downloader via DI so CacheManager is environment-agnostic
    let downloader: any EpisodeCachingDownloader = Container.shared.cacheEpisodeDownloader()
    return try await downloader.start(podcastEpisode)
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
          await handleQueueChange(queuedEpisodes)
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
      return
    }

    // Cancel background task if present
    if let episode: Episode = try await CacheError.catch({ try await repo.episode(episodeID) }) {
      let mg = MediaGUID(guid: episode.unsaved.guid, media: episode.unsaved.media)
      if let taskID = await Container.shared.cacheTaskMapStore().taskID(for: mg) {
        await cacheManagerSession.cancelDownload(taskID: taskID)
        await Container.shared.cacheTaskMapStore().remove(taskID: taskID)
        await cacheState.removeDownloadTask(episodeID)
        return
      }
    }

    try await clearCache(for: episodeID)
  }

  static func generateCacheFilename(for episode: Episode) -> String {
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

  // MARK: - Background Session Adoption

  private func adoptInFlightBackgroundDownloads() async {
    let taskIDs = await cacheManagerSession.listDownloadTaskIDs()

    let taskMap = Container.shared.cacheTaskMapStore()
    for taskID in taskIDs {
      if let mg = await taskMap.key(for: taskID) {
        do {
          if let episode = try await repo.episode(mg) {
            await cacheState.setDownloadTaskIdentifier(episode.id, taskIdentifier: taskID)
            Self.log.debug("adoptInFlight: episode \(episode.id) task #\(taskID)")
          }
        } catch {
          Self.log.error(error)
        }
      }
    }
  }
}
