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
      // Cap the overall per-download deadline (which includes time spent waiting
      // for connectivity) well below the framework's multi-day default, so a
      // download that never makes progress is abandoned in bounded time.
      // Genuinely dead tasks (e.g. cancelled by a force-quit, which never
      // deliver a completion callback) are reset by reconcileStaleDownloads().
      config.timeoutIntervalForResource = 24 * 60 * 60
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
  // Completion latches for in-flight downloads, keyed by episode. downloadToCache
  // registers one when a download starts; CacheBackgroundDelegate opens and
  // removes whatever latch occupies the episode's slot on the terminal callback,
  // resuming any caller suspended in cachedURL(downloadingIfNeeded:). The key is
  // the episode, not the attempt, so this assumes a single in-flight attempt per
  // episode: the failure-path signal fires synchronously right after the
  // downloading flag is cleared, leaving no realistic gap for a replacement
  // attempt to register its own latch before the prior signal lands.
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

      // Reconcile stranded downloads before observing: a stale downloading flag
      // must be cleared before the current-episode/queue observers see it, or
      // they skip the re-download as "already caching" and the flag is then
      // reconciled away, leaving the episode uncached with no active download.
      Task(priority: taskPriority(.utility)) {
        await reconcileStaleDownloads()
        startCurrentEpisodeIDObservation()
        startQueueObservation()
      }
    }
  }

  // A download tracked as in-flight (downloading == true) is normally cleared
  // only by the delegate's terminal callbacks, but a force-quit cancels the
  // background tasks without delivering them, stranding the flag set. On launch
  // the recreated session re-lists only the still-live tasks, so any downloading
  // row absent from that set is dead and gets cleared. Reading the DB rows
  // before the live-task snapshot is deliberate: downloadToCache creates the
  // task before flipping the flag, so a genuinely in-flight download can never
  // appear in the rows yet be missing from the snapshot.
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
    // Register this attempt's completion latch before resuming, so an awaiter
    // always finds it and the delegate's terminal callback can open it.
    downloadLatches[podcastEpisode.id] = AsyncLatch<Void>()
    downloadTask.resume()

    return downloadTask.taskID
  }

  // Ensures the episode's audio is cached, starting a download if needed, and
  // suspends until it finishes. Returns the cached URL, or nil if the episode
  // vanished or the download failed. Event-driven via AsyncLatch — no polling.
  func cachedURL(downloadingIfNeeded episodeID: Episode.ID) async throws -> CachedURL? {
    if let cachedURL = try await repo.episode(episodeID)?.cachedURL { return cachedURL }

    try await downloadToCache(for: episodeID)
    // downloadToCache no-ops when already cached/caching, so re-check rather
    // than await a latch whose completion may have already fired.
    guard let episode = try await repo.episode(episodeID) else { return nil }
    if let cachedURL = episode.cachedURL { return cachedURL }
    guard try await ensureDownloadIsActive(episode) else {
      return try await repo.episode(episodeID)?.cachedURL
    }

    // Suspend until the in-flight download's terminal callback opens its latch.
    // A download reattached after a relaunch has a live task but no latch (the
    // map is in-memory and empty on launch), so adopt the existing latch or
    // register one. Then re-check liveness: if the task already finished its
    // signal found no latch, so don't await — read the result directly.
    let latch = downloadLatches { latches -> AsyncLatch<Void> in
      if let existing = latches[episodeID] { return existing }
      let fresh = AsyncLatch<Void>()
      latches[episodeID] = fresh
      return fresh
    }
    if await hasLiveDownloadTask(for: episodeID) {
      try await latch.wait()
    }
    return try await repo.episode(episodeID)?.cachedURL
  }

  // Opens and removes the in-flight download's completion latch for an episode
  // whose download just finished or failed, resuming any awaiter. A no-op when
  // no download is registered.
  func signalDownloadComplete(for episodeID: Episode.ID) {
    downloadLatches { $0.removeValue(forKey: episodeID) }?.open()
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

  private func ensureDownloadIsActive(_ episode: Episode) async throws -> Bool {
    guard episode.cachedURL == nil else { return false }

    let episodeID = episode.id
    switch episode.cacheStatus {
    case .cached:
      return false
    case .uncached:
      try await downloadToCache(for: episodeID)
      return await hasLiveDownloadTask(for: episodeID)
    case .caching:
      guard !(await hasLiveDownloadTask(for: episodeID)) else { return true }
      Self.log.debug("ensureDownloadIsActive: restarting stranded download for \(episodeID)")
      try await repo.updateDownloading(episodeID, downloading: false)
      try await downloadToCache(for: episodeID)
      return await hasLiveDownloadTask(for: episodeID)
    }
  }

  private func hasLiveDownloadTask(for episodeID: Episode.ID) async -> Bool {
    let description = String(episodeID.rawValue)
    return await cacheManagerSession.allCreatedTasks.contains {
      $0.taskDescription == description
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
