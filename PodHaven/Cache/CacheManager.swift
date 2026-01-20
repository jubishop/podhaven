// Copyright Justin Bishop, 2025

import Combine
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import Nuke
import Sharing
import Tagged
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

struct CacheManager {
  @DynamicInjected(\.cacheManagerSession) private var cacheManagerSession
  @DynamicInjected(\.notifications) private var notifications
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.sleeper) private var sleeper

  private var alert: Alert { get async { await Container.shared.alert() } }
  private var fileManager: any FileManaging { Container.shared.fileManager() }

  private static let log = Log.as(LogSubsystem.Cache.manager)

  // MARK: - State Management

  private let currentOnDeckEpisodeID = ThreadSafe<Episode.ID?>(nil)
  private let currentQueuedEpisodeIDs = ThreadSafe<Set<Episode.ID>>([])

  // MARK: - Initialization

  fileprivate init() {}

  func start() {
    guard Function.neverCalled() else { return }

    Self.log.debug("start: executing")

    do {
      try fileManager.createDirectory(
        at: Self.cacheDirectory,
        withIntermediateDirectories: true
      )
    } catch {
      Assert.fatal("Couldn't create cache directory?")
    }

    startOnDeckObservation()
    startQueueObservation()
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

    guard podcastEpisode.episode.cacheStatus != .cached
    else {
      Self.log.trace("\(podcastEpisode.toString) already cached")
      return nil
    }

    guard podcastEpisode.episode.cacheStatus != .caching
    else {
      Self.log.trace("\(podcastEpisode.toString) already being downloaded")
      return nil
    }

    var request = URLRequest(url: podcastEpisode.episode.mediaURL.rawValue)
    request.allowsExpensiveNetworkAccess = true
    request.allowsConstrainedNetworkAccess = true

    let downloadTask = cacheManagerSession.createDownloadTask(with: request)
    downloadTask.resume()

    try await repo.updateDownloadTaskID(podcastEpisode.id, downloadTaskID: downloadTask.taskID)

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

    guard await Self.canClearCache(episode)
    else {
      Self.log.debug("Can't clear cache for: \(episode.toString)")
      return nil
    }

    if let taskID = episode.downloadTaskID {
      await cacheManagerSession.allCreatedTasks[id: taskID]?.cancel()
      sharedState.clearDownloadProgress(for: episodeID)
      try await repo.updateDownloadTaskID(episode.id, downloadTaskID: nil)
    }

    guard let cachedURL = episode.cachedURL
    else {
      Self.log.debug("episode: \(episode.toString) has no cached file")
      return nil
    }

    try await repo.updateCachedFilename(episode.id, cachedFilename: nil)
    try fileManager.removeItem(at: cachedURL.rawValue)

    Self.log.debug("cache cleared for: \(episode.toString)")

    return cachedURL
  }

  // MARK: - Private Helpers

  private func startOnDeckObservation() {
    Assert.neverCalled()

    Self.log.debug("startOnDeckObservation: starting")

    Task(priority: .utility) {
      for await onDeck in sharedState.$onDeck.publisher.values {
        await handleOnDeckChange(onDeck)
      }
    }
  }

  private func handleOnDeckChange(_ onDeck: OnDeck?) async {
    guard let onDeck else {
      currentOnDeckEpisodeID(nil)
      return
    }

    let episodeID = onDeck.id

    guard currentOnDeckEpisodeID() != episodeID else { return }
    currentOnDeckEpisodeID(episodeID)

    Self.log.debug("handleOnDeckChange: new on deck episode: \(episodeID)")

    Task {
      do {
        try await downloadToCache(for: episodeID)
      } catch {
        Self.log.error(error)
      }
    }
  }

  private func startQueueObservation() {
    Assert.neverCalled()

    Self.log.debug("startQueueObservation: starting")

    Task(priority: .utility) {
      for await episodes in sharedState.queuedPodcastEpisodesStream() {
        let queuedEpisodeIDs = Set(episodes.map(\.episode.id))
        await handleQueueChange(queuedEpisodeIDs)
      }
    }
  }

  private func handleQueueChange(_ queuedEpisodeIDs: Set<Episode.ID>) async {
    let newEpisodeIDs = queuedEpisodeIDs.subtracting(currentQueuedEpisodeIDs())
    currentQueuedEpisodeIDs(queuedEpisodeIDs)

    Self.log.debug(
      """
      handleQueueChange:
        new queue IDs: 
          \(newEpisodeIDs)
      """
    )

    await withDiscardingTaskGroup { group in
      for episodeID in newEpisodeIDs {
        group.addTask { [episodeID] in
          do {
            try await downloadToCache(for: episodeID)
          } catch {
            Self.log.error(error)
          }
        }
      }
    }
  }

  // MARK: - Static Helpers

  @MainActor
  static func canClearCache(_ episode: any EpisodeInformable) -> Bool {
    guard !episode.queued else { return false }
    guard let currentEpisodeID = Container.shared.sharedState().currentEpisodeID else {
      return true
    }
    return currentEpisodeID != episode.episodeID
  }

  static func resolveCachedFilepath(for fileName: String) -> CachedURL {
    Assert.precondition(!fileName.isEmpty, "Empty fileName in resolveCachedFilepath?")

    return CachedURL(cacheDirectory.appendingPathComponent(fileName))
  }

  static var cacheDirectory: URL {
    AppInfo.applicationSupportDirectory.appendingPathComponent("episodes")
  }
}
