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
      // Abandon downloads that never finish in bounded time, below the
      // framework's week-scale default. The resource timer also counts time
      // spent waiting for connectivity, so leave headroom for offline
      // stretches; force-quit leaks are cleared by reconcileStaleDownloads().
      config.timeoutIntervalForResource = 3 * 24 * 60 * 60
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

struct CacheDownloadAttempt: Hashable, Sendable {
  let episodeID: Episode.ID
  let taskID: URLSessionDownloadTask.ID
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
  private let activeDownloadAttempts = ThreadSafe<[Episode.ID: CacheDownloadAttempt]>([:])
  private let downloadLatches = ThreadSafe<[CacheDownloadAttempt: AsyncLatch<Void>]>([:])

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

      // Reconcile before observing: observers would skip a stale "downloading"
      // row as already-caching, then reconcile clears it, leaving it uncached.
      Task(priority: taskPriority(.utility)) {
        await reconcileStaleDownloads()
        startCurrentEpisodeIDObservation()
        startQueueObservation()
      }
    }
  }

  // Clear downloading flags stranded by a force-quit, which cancels background
  // tasks without delivering their callbacks: any downloading row absent from
  // the recreated session's live tasks is dead.
  private func reconcileStaleDownloads() async {
    do {
      let downloadingIDs = try await repo.downloadingEpisodeIDs()
      guard !downloadingIDs.isEmpty else { return }

      let liveDescriptions = Set(
        await cacheManagerSession.allCreatedTasks.compactMap(\.taskDescription)
      )
      for episodeID in downloadingIDs
      where !liveDescriptions.contains(String(episodeID.rawValue)) {
        Self.log.debug("reconcileStaleDownloads: clearing stranded download for \(episodeID)")
        try await repo.updateDownloading(episodeID, downloading: false)
      }
    } catch {
      Self.log.caughtError("reconcileStaleDownloads failed", error)
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

    guard let attempt = try await startDownload(for: podcastEpisode) else { return nil }
    return attempt.taskID
  }

  func cachedURL(downloadingIfNeeded episodeID: Episode.ID) async throws -> CachedURL? {
    guard let podcastEpisode = try await repo.podcastEpisode(episodeID) else {
      Self.log.warning("Episode \(episodeID) not found for cache operation")
      return nil
    }

    let attempt: CacheDownloadAttempt
    switch podcastEpisode.episode.cacheStatus {
    case .cached:
      if let cachedURL = podcastEpisode.episode.cachedURL,
        fileManager.fileExists(at: cachedURL.rawValue)
      {
        return cachedURL
      }
      // The row says cached but the file is gone (e.g. an interrupted
      // clearCache): clear the stale filename and download fresh.
      Self.log.warning("cachedURL: cached file missing on disk for \(episodeID), re-downloading")
      try await repo.updateCachedFilename(episodeID, cachedFilename: nil)
      guard let startedAttempt = try await startOrJoinDownload(for: podcastEpisode) else {
        return try await repo.episode(episodeID)?.cachedURL
      }
      attempt = startedAttempt
    case .uncached:
      guard let startedAttempt = try await startOrJoinDownload(for: podcastEpisode) else {
        return try await repo.episode(episodeID)?.cachedURL
      }
      attempt = startedAttempt
    case .caching:
      if let activeAttempt = await activeDownloadAttempt(for: episodeID) {
        attempt = activeAttempt
      } else {
        Self.log.debug("cachedURL: restarting stranded download for \(episodeID)")
        try await repo.updateDownloading(episodeID, downloading: false)
        guard let restartedAttempt = try await startOrJoinDownload(for: podcastEpisode) else {
          return try await repo.episode(episodeID)?.cachedURL
        }
        attempt = restartedAttempt
      }
    }

    // Register before re-reading state so a completion after this point opens
    // the latch rather than signaling an empty slot.
    let latch = downloadLatches { latches -> AsyncLatch<Void> in
      if let existing = latches[attempt] { return existing }
      let fresh = AsyncLatch<Void>()
      latches[attempt] = fresh
      return fresh
    }

    // Re-read after registering: downloading is cleared before the signal, so
    // still-downloading means the signal is still coming.
    guard let current = try await repo.episode(episodeID) else {
      signalDownloadComplete(for: attempt)
      return nil
    }
    if let cachedURL = current.cachedURL {
      signalDownloadComplete(for: attempt)
      return cachedURL
    }
    guard current.downloading, activeDownloadAttempts[episodeID] == attempt else {
      signalDownloadComplete(for: attempt)
      return nil
    }
    try await latch.wait()
    return try await repo.episode(episodeID)?.cachedURL
  }

  func signalDownloadComplete(for attempt: CacheDownloadAttempt) {
    activeDownloadAttempts { attempts in
      guard attempts[attempt.episodeID] == attempt else { return }
      attempts.removeValue(forKey: attempt.episodeID)
    }
    downloadLatches { $0.removeValue(forKey: attempt) }?.open()
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
      if let activeAttempt = await activeDownloadAttempt(for: episodeID) {
        let liveTask = await cacheManagerSession.allCreatedTasks.first {
          $0.taskID == activeAttempt.taskID
        }
        liveTask?.cancel()
      }
      sharedState.clearDownloadProgress(for: episodeID)
      try await repo.updateDownloading(episodeID, downloading: false)
    }

    guard let cachedURL = episode.cachedURL else {
      Self.log.debug("episode: \(episode.toString) has no cached file")
      return nil
    }

    do {
      try fileManager.removeItem(at: cachedURL.rawValue)
    } catch {
      guard ErrorKit.isMissingFile(error) else {
        Self.log.caughtError(
          "clearCache: failed to remove cached file for \(episode.toString)",
          error
        )
        throw error
      }
      Self.log.caughtError(
        "clearCache: cached file already missing for \(episode.toString)",
        error,
        level: .debug
      )
    }
    try await repo.updateCachedFilename(episode.id, cachedFilename: nil)

    Self.log.debug("cache cleared for: \(episode.toString)")
    return cachedURL
  }

  // MARK: - Private Helpers

  @discardableResult
  private func startDownload(for podcastEpisode: PodcastEpisode) async throws
    -> CacheDownloadAttempt?
  {
    guard try await repo.claimForDownloadIfUncached(podcastEpisode.id) else {
      Self.log.trace("startDownload: episode \(podcastEpisode.id) was not uncached")
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
    let attempt = CacheDownloadAttempt(
      episodeID: podcastEpisode.id,
      taskID: downloadTask.taskID
    )
    activeDownloadAttempts[podcastEpisode.id] = attempt
    downloadTask.resume()
    return attempt
  }

  private func startOrJoinDownload(for podcastEpisode: PodcastEpisode) async throws
    -> CacheDownloadAttempt?
  {
    if let attempt = try await startDownload(for: podcastEpisode) { return attempt }
    return await activeDownloadAttempt(for: podcastEpisode.id)
  }

  private func activeDownloadAttempt(for episodeID: Episode.ID) async -> CacheDownloadAttempt? {
    if let activeAttempt = activeDownloadAttempts[episodeID] { return activeAttempt }

    let description = String(episodeID.rawValue)
    guard
      let task = await cacheManagerSession.allCreatedTasks.first(where: {
        $0.taskDescription == description
      })
    else { return nil }

    let reattachedAttempt = CacheDownloadAttempt(episodeID: episodeID, taskID: task.taskID)
    return activeDownloadAttempts { attempts in
      if let activeAttempt = attempts[episodeID] { return activeAttempt }
      attempts[episodeID] = reattachedAttempt
      return reattachedAttempt
    }
  }

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
