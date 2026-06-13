// Copyright Justin Bishop, 2025

import Combine
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import Nuke
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
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState

  private var alert: Alert { get async { await Container.shared.alert() } }
  private var fileManager: any FileManaging { Container.shared.fileManager() }
  private var taskPriority: @Sendable (TaskPriority?) -> TaskPriority? {
    Container.shared.taskPriority()
  }

  private static let log = Log.as(LogSubsystem.Cache.manager)

  // MARK: - State Management

  private let startOnce = Once()
  private let currentQueuedEpisodeIDs = ThreadSafe<Set<Episode.ID>>([])
  // One-shot completion signals for in-flight downloads, keyed by episode.
  // CacheBackgroundDelegate opens a latch when a download finishes or fails, so
  // callers can await a download instead of polling for the cached file.
  private let downloadLatches = ThreadSafe<[Episode.ID: AsyncLatch<Void>]>([:])

  // MARK: - Initialization

  fileprivate init() {}

  func start() {
    startOnce.run {
      Self.log.debug("start: executing")

      do {
        try fileManager.createDirectory(
          at: Self.cacheDirectory,
          withIntermediateDirectories: true
        )
      } catch {
        Assert.fatal("Couldn't create cache directory?")
      }

      startCurrentEpisodeIDObservation()
      startQueueObservation()
    }
  }

  // MARK: - Public Methods

  @discardableResult
  func downloadToCache(for episodeID: Episode.ID) async throws -> URLSessionDownloadTask.ID? {
    Self.log.trace("downloadToCache: \(episodeID)")

    let podcastEpisode = try await repo.podcastEpisode(episodeID)
    guard let podcastEpisode else {
      Self.log.warning("Episode \(episodeID) not found for cache operation")
      return nil
    }

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

    // taskDescription is the stable per-episode identifier the delegate uses
    // to map a finished download back to its episode. Setting it BEFORE
    // resume() guarantees it's there when the system invokes any callback,
    // including across an app relaunch that reattaches to this background
    // session.
    let downloadTask = cacheManagerSession.createDownloadTask(
      with: request,
      taskDescription: String(podcastEpisode.id.rawValue)
    )
    try await repo.updateDownloading(podcastEpisode.id, downloading: true)
    downloadTask.resume()

    return downloadTask.taskID
  }

  // Ensures the episode's audio is cached, starting a download if needed, and
  // suspends until it finishes. Returns the cached URL, or nil if the episode
  // vanished or the download failed. Event-driven via AsyncLatch — no polling.
  func cachedURL(downloadingIfNeeded episodeID: Episode.ID) async throws -> CachedURL? {
    // Register the latch before inspecting state so a completion that fires
    // mid-flight can't slip between the cache check and the await.
    let latch = downloadLatches { latches in
      let latch = latches[episodeID] ?? AsyncLatch<Void>()
      latches[episodeID] = latch
      return latch
    }
    defer { downloadLatches { _ = $0.removeValue(forKey: episodeID) } }

    if let cachedURL = try await repo.episode(episodeID)?.cachedURL { return cachedURL }

    try await downloadToCache(for: episodeID)
    // downloadToCache no-ops when already cached/caching, so re-check rather
    // than await a latch whose completion may have already fired.
    if let cachedURL = try await repo.episode(episodeID)?.cachedURL { return cachedURL }

    try await latch.wait()
    return try await repo.episode(episodeID)?.cachedURL
  }

  // Opens the completion latch for an episode whose download just finished or
  // failed. A no-op when nothing is awaiting it.
  func signalDownloadComplete(for episodeID: Episode.ID) {
    downloadLatches { $0[episodeID] }?.open()
  }

  @discardableResult
  func clearCache(for episodeID: Episode.ID) async throws -> CachedURL? {
    Self.log.debug("clearCache: \(episodeID)")

    let episode = try await repo.episode(episodeID)
    guard let episode else {
      Self.log.warning("Episode \(episodeID) not found for cache operation")
      return nil
    }

    guard await Self.canClearCache(episode)
    else {
      Self.log.debug("Can't clear cache for: \(episode.toString)")
      return nil
    }

    if episode.downloading {
      let description = String(episodeID.rawValue)
      let liveTask = await cacheManagerSession.allCreatedTasks.first {
        $0.taskDescription == description
      }
      liveTask?.cancel()
      sharedState.clearDownloadProgress(for: episodeID)
      try await repo.updateDownloading(episode.id, downloading: false)
    }

    guard let cachedURL = episode.cachedURL
    else {
      Self.log.debug("episode: \(episode.toString) has no cached file")
      return nil
    }

    do {
      try fileManager.removeItem(at: cachedURL.rawValue)
    } catch {
      Self.log.caughtError(
        "clearCache: failed to remove cached file for \(episode.toString)",
        error
      )
    }
    try await repo.updateCachedFilename(episode.id, cachedFilename: nil)

    Self.log.debug("cache cleared for: \(episode.toString)")

    return cachedURL
  }

  // MARK: - Private Helpers

  private func startCurrentEpisodeIDObservation() {
    Self.log.debug("startCurrentEpisodeIDObservation: starting")

    Task(priority: taskPriority(.utility)) {
      for await episodeID in sharedState.$currentEpisodeID.stream() {
        guard let episodeID else { continue }
        Self.log.debug("handleCurrentEpisodeIDChange: new episode: \(episodeID)")
        do {
          try await downloadToCache(for: episodeID)
        } catch {
          Self.log.caughtError(
            "handleCurrentEpisodeIDChange: failed to cache episode \(episodeID)",
            error
          )
        }
      }
    }
  }

  private func startQueueObservation() {
    Self.log.debug("startQueueObservation: starting")

    Task(priority: taskPriority(.utility)) {
      for await episodes in sharedState.$queuedPodcastEpisodes.stream() {
        let queuedEpisodeIDs = Set(episodes.map(\.id))
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
            Self.log.caughtError(
              "handleQueueChange: failed to cache episode \(episodeID)",
              error
            )
          }
        }
      }
    }
  }

  // MARK: - Static Helpers

  @MainActor
  static func canClearCache(_ episode: any EpisodeFoundational) -> Bool {
    guard !episode.queued else { return false }
    guard let currentEpisodeID = Container.shared.sharedState().$currentEpisodeID.value else {
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
