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
  }

  // MARK: - Public Methods

  @discardableResult
  func downloadToCache(for episodeID: Episode.ID) async throws(CacheError) -> Bool {
    Self.log.trace("downloadToCache: \(episodeID)")

    return try await CacheError.catch {
      try await performDownloadToCache(episodeID)
    }
  }
  private func performDownloadToCache(_ episodeID: Episode.ID) async throws -> Bool {
    let podcastEpisode = try await repo.podcastEpisode(episodeID)
    guard let podcastEpisode
    else { throw CacheError.episodeNotFound(episodeID) }

    guard !podcastEpisode.episode.cached
    else {
      Self.log.trace("downloadToCache: \(podcastEpisode.toString) already cached")
      return false
    }

    guard !podcastEpisode.episode.caching
    else {
      Self.log.trace("downloadToCache: \(podcastEpisode.toString) already being downloaded")
      return false
    }

    await imageFetcher.prefetch([podcastEpisode.image])

    var request = URLRequest(url: podcastEpisode.episode.media.rawValue)
    request.allowsExpensiveNetworkAccess = true
    request.allowsConstrainedNetworkAccess = true

    let downloadTask = cacheManagerSession.createDownloadTask(with: request)
    downloadTask.resume()

    try await repo.updateDownloadTaskID(podcastEpisode.id, downloadTask.taskID)

    return true
  }

  @discardableResult
  func clearCache(for episodeID: Episode.ID) async throws(CacheError) -> Bool {
    Self.log.debug("clearCache: \(episodeID)")

    return try await CacheError.catch {
      try await performClearCache(episodeID)
    }
  }
  private func performClearCache(_ episodeID: Episode.ID) async throws -> Bool {
    let episode = try await repo.episode(episodeID)
    guard let episode
    else { throw CacheError.episodeNotFound(episodeID) }

    guard !episode.queued
    else {
      Self.log.trace("clearCache: still queued, keeping cache for: \(episode.toString)")
      return false
    }

    if let onDeck = await playState.onDeck, onDeck == episode {
      Self.log.trace("clearCache: currently playing, keeping cache for: \(episode.toString)")
      return false
    }

    if let taskID = episode.downloadTaskID {
      await cacheManagerSession.allCreatedTasks[id: taskID]?.cancel()
      try await repo.updateDownloadTaskID(episode.id, nil)
    }

    guard let cachedFilename = episode.cachedFilename
    else {
      Self.log.trace("clearCache: episode: \(episode.toString) has no cached filename")
      return false
    }

    try await repo.updateCachedFilename(episode.id, nil)
    let cacheURL = Self.resolveCachedFilepath(for: cachedFilename)
    try await Container.shared.podFileManager().removeItem(at: cacheURL)

    Self.log.debug("clearCache: cache cleared for: \(episode.toString)")

    return true
  }

  // MARK: - Private Helpers

  private func startMonitoringQueue() {
    Assert.neverCalled()

    Self.log.debug("startMonitoringQueue: starting")

    Task(priority: .utility) { [weak self] in
      guard let self else { return }

      do {
        for try await queuedEpisodes in await observatory.queuedPodcastEpisodes() {
          await handleQueueChange(queuedEpisodes.map(\.id))
        }
      } catch {
        Self.log.error(error)
        await alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  private func handleQueueChange(_ queuedEpisodeIDsList: [Episode.ID]) async {
    let queuedEpisodeIDs = Set(queuedEpisodeIDsList)
    let removedEpisodeIDs = currentQueuedEpisodeIDs.subtracting(queuedEpisodeIDs)
    currentQueuedEpisodeIDs = queuedEpisodeIDs

    Self.log.debug(
      """
      handleQueueChange:
        current queue IDs: 
          \(queuedEpisodeIDsList)
        removed IDs: 
          \(removedEpisodeIDs)
      """
    )

    await withDiscardingTaskGroup { group in
      for episodeID in queuedEpisodeIDsList {
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

  static func generateCacheFilename(for episode: Episode) -> String {
    let mediaURL = episode.media.rawValue
    let fileExtension =
      mediaURL.pathExtension.isEmpty == false
      ? mediaURL.pathExtension
      : "mp3"
    return "\(mediaURL.hash(to: 12)).\(fileExtension)"
  }

  static func resolveCachedFilepath(for fileName: String) -> URL {
    Assert.precondition(!fileName.isEmpty, "Empty fileName in resolveCachedFilepath?")

    return cacheDirectory.appendingPathComponent(fileName)
  }

  private static var cacheDirectory: URL {
    AppInfo.applicationSupportDirectory.appendingPathComponent("episodes")
  }
}
