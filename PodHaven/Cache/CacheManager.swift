// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import Nuke
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
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.podFileManager) private var podFileManager
  @DynamicInjected(\.repo) private var repo

  private var alert: Alert { get async { await Container.shared.alert() } }
  private var cacheState: CacheState { get async { await Container.shared.cacheState() } }
  private var playState: PlayState { get async { await Container.shared.playState() } }

  private static let log = Log.as(LogSubsystem.Cache.cacheManager)

  // MARK: - State Management

  private let prefetcher = ImagePrefetcher(pipeline: Container.shared.imagePipeline())
  private var currentQueuedEpisodeIDs: Set<Episode.ID> = []

  // MARK: - Initialization

  fileprivate init() {}

  func start() async throws {
    Self.log.debug("start: executing")

    try podFileManager.createDirectory(
      at: Self.cacheDirectory,
      withIntermediateDirectories: true
    )
    startMonitoringQueue()
  }

  // MARK: - Public Methods

  @discardableResult
  func downloadToCache(for episodeID: Episode.ID) async throws(CacheError)
    -> URLSessionDownloadTask.ID?
  {
    Self.log.trace("downloadToCache: \(episodeID)")

    return try await CacheError.catch {
      try await performDownloadToCache(episodeID)
    }
  }
  private func performDownloadToCache(_ episodeID: Episode.ID) async throws
    -> URLSessionDownloadTask.ID?
  {
    let podcastEpisode = try await repo.podcastEpisode(episodeID)
    guard let podcastEpisode
    else { throw CacheError.episodeNotFound(episodeID) }

    guard !podcastEpisode.episode.cached
    else {
      Self.log.trace("\(podcastEpisode.toString) already cached")
      return nil
    }

    guard !podcastEpisode.episode.caching
    else {
      Self.log.trace("\(podcastEpisode.toString) already being downloaded")
      return nil
    }

    prefetcher.startPrefetching(with: [podcastEpisode.image])

    var request = URLRequest(url: podcastEpisode.episode.mediaURL.rawValue)
    request.allowsExpensiveNetworkAccess = true
    request.allowsConstrainedNetworkAccess = true

    let downloadTask = cacheManagerSession.createDownloadTask(with: request)
    downloadTask.resume()

    try await repo.updateDownloadTaskID(podcastEpisode.id, downloadTask.taskID)

    return downloadTask.taskID
  }

  @discardableResult
  func clearCache(for episodeID: Episode.ID) async throws(CacheError) -> CachedURL? {
    Self.log.debug("clearCache: \(episodeID)")

    return try await CacheError.catch {
      try await performClearCache(episodeID)
    }
  }
  private func performClearCache(_ episodeID: Episode.ID) async throws -> CachedURL? {
    let episode = try await repo.episode(episodeID)
    guard let episode
    else { throw CacheError.episodeNotFound(episodeID) }

    guard !episode.queued
    else {
      Self.log.debug("still queued, keeping cache for: \(episode.toString)")
      return nil
    }

    if let onDeck = await playState.onDeck, onDeck == episode {
      Self.log.debug("currently playing, keeping cache for: \(episode.toString)")
      return nil
    }

    if let taskID = episode.downloadTaskID {
      await cacheManagerSession.allCreatedTasks[id: taskID]?.cancel()
      await cacheState.clearProgress(for: episodeID)
      try await repo.updateDownloadTaskID(episode.id, nil)
    }

    guard let cachedURL = episode.cachedURL
    else {
      Self.log.debug("episode: \(episode.toString) has no cached file")
      return nil
    }

    try await repo.updateCachedFilename(episode.id, nil)
    try podFileManager.removeItem(at: cachedURL.rawValue)

    Self.log.debug("cache cleared for: \(episode.toString)")

    return cachedURL
  }

  // MARK: - Private Helpers

  private func startMonitoringQueue() {
    Assert.neverCalled()

    Self.log.debug("startMonitoringQueue: starting")

    Task(priority: .utility) { [weak self] in
      guard let self else { return }

      do {
        for try await queuedEpisodeIDs in await observatory.queuedEpisodeIDs() {
          await handleQueueChange(queuedEpisodeIDs)
        }
      } catch {
        Self.log.error(error)
        await alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  private func handleQueueChange(_ queuedEpisodeIDs: Set<Episode.ID>) async {
    let newEpisodeIDs = queuedEpisodeIDs.subtracting(currentQueuedEpisodeIDs)
    let removedEpisodeIDs = currentQueuedEpisodeIDs.subtracting(queuedEpisodeIDs)
    currentQueuedEpisodeIDs = queuedEpisodeIDs

    Self.log.debug(
      """
      handleQueueChange:
        new queue IDs: 
          \(newEpisodeIDs)
        removed IDs: 
          \(removedEpisodeIDs)
      """
    )

    await withDiscardingTaskGroup { group in
      for episodeID in newEpisodeIDs {
        group.addTask { [weak self] in
          guard let self else { return }
          do {
            try await downloadToCache(for: episodeID)
          } catch {
            Self.log.error(error)
          }
        }
      }

      for episodeID in removedEpisodeIDs {
        group.addTask { [weak self] in
          guard let self else { return }
          do {
            try await clearCache(for: episodeID)
          } catch {
            Self.log.error(error)
          }
        }
      }
    }
  }

  // MARK: - Static Helpers

  static func resolveCachedFilepath(for fileName: String) -> CachedURL {
    Assert.precondition(!fileName.isEmpty, "Empty fileName in resolveCachedFilepath?")

    return CachedURL(cacheDirectory.appendingPathComponent(fileName))
  }

  private static var cacheDirectory: URL {
    AppInfo.applicationSupportDirectory.appendingPathComponent("episodes")
  }
}
