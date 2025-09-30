// Copyright Justin Bishop, 2025

import BackgroundTasks
import ConcurrencyExtras
import FactoryKit
import Foundation
import Logging

extension Container {
  var cachePurger: Factory<CachePurger> {
    Factory(self) { CachePurger() }.scope(.cached)
  }
}

final class CachePurger: Sendable {
  private var cacheManager: CacheManager { Container.shared.cacheManager() }
  private var podFileManager: any FileManageable { Container.shared.podFileManager() }
  private var repo: any Databasing { Container.shared.repo() }

  private static let backgroundTaskIdentifier = "com.justinbishop.podhaven.cachePurge"

  private static let log = Log.as(LogSubsystem.Cache.purger)

  // MARK: - Configuration

  private let cacheSizeLimit: Int64 = 500 * 1024 * 1024  // 500 MB
  private let cadence: Duration = .hours(2)
  private let oldEpisodeThreshold: Duration = .days(2)

  // MARK: - State Management

  private let purgeLock = ThreadLock()
  private let bgTask = ThreadSafe<Task<Bool, Never>?>(nil)

  // MARK: - Initialization

  fileprivate init() {}

  func start() {
    guard Function.neverCalled() else { return }

    Self.log.debug("start: executing")

    schedule(in: cadence)
  }

  // MARK: - Background Task Scheduling

  func register() {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: Self.backgroundTaskIdentifier,
      using: nil
    ) { [weak self] task in
      guard let self else { return }

      let taskWrapper = UncheckedSendable(task)
      let didComplete = ThreadSafe(false)
      let complete: @Sendable (Bool) -> Void = { [didComplete, taskWrapper] success in
        guard !didComplete() else { return }
        didComplete(true)
        taskWrapper.value.setTaskCompleted(success: success)
      }

      task.expirationHandler = { [weak self, complete] in
        guard let self else { return }

        Self.log.debug("handle: expiration triggered, cancelling running task")

        bgTask()?.cancel()
        bgTask(nil)
        complete(false)
      }

      schedule(in: cadence)

      Task { [weak self, complete] in
        guard let self
        else {
          complete(false)
          return
        }

        let success = await executeBGTask()
        complete(success)
      }
    }
  }

  func schedule(in duration: Duration) {
    let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
    request.earliestBeginDate = Date.now.advanced(by: duration.asTimeInterval)

    do {
      try BGTaskScheduler.shared.submit(request)
      Self.log.debug("scheduled next cache purge in: \(duration)")
    } catch {
      Self.log.error(error)
    }
  }

  // MARK: - Background Task

  private func executeBGTask() async -> Bool {
    Self.log.debug("bgTask: performing cache purge")

    let task: Task<Bool, Never> = Task(priority: .background) { [weak self] in
      guard let self else { return false }

      do {
        try await executePurge()
        return true
      } catch {
        Self.log.error(error)
        return false
      }
    }

    bgTask(task)
    let success = await task.value
    bgTask(nil)

    Self.log.debug("bgTask: cache purge completed gracefully")

    return success
  }

  // MARK: - Purge Logic

  func executePurge() async throws {
    if !purgeLock.claim() {
      Self.log.debug("failed to claim purge lock: already purging")
      return
    }
    defer { purgeLock.release() }

    // Get cached episodes once
    let cachedEpisodes = try await repo.cachedEpisodes()

    // First, purge any dangling files (files with no associated episode)
    try await purgeDanglingFiles(cachedEpisodes: cachedEpisodes)

    // Validate that cached episodes still have their files on disk
    try await validateCachedEpisodes(cachedEpisodes: cachedEpisodes)

    // Calculate total cache size
    let totalSize = try calculateCacheSize()
    Self.log.debug(
      "cache size: \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))"
    )

    guard totalSize > cacheSizeLimit
    else {
      Self.log.debug("cache size within limit, no purge needed")
      return
    }

    let bytesToFree = totalSize - cacheSizeLimit
    Self.log.debug(
      "freeing: \(ByteCountFormatter.string(fromByteCount: bytesToFree, countStyle: .file))"
    )

    // Get cached episodes in deletion priority order
    let episodesToDelete = try await getCachedEpisodesInDeletionOrder(
      cachedEpisodes: cachedEpisodes
    )

    var freedBytes: Int64 = 0
    var deletedCount = 0

    for episode in episodesToDelete {
      guard freedBytes < bytesToFree else { break }

      if let cachedURL = episode.cachedURL {
        do {
          let fileSize = try podFileManager.fileSize(for: cachedURL.rawValue)
          if let clearedURL = try await cacheManager.clearCache(for: episode.id) {
            freedBytes += fileSize
            deletedCount += 1
            Self.log.debug(
              """
                deleted: \(episode.toString)
                cached file: \(clearedURL.lastPathComponent)
                bytes: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
              """
            )
          }
        } catch {
          Self.log.error(error)
        }
      }
    }

    Self.log.debug(
      """
      purge completed:
        deleted: \(deletedCount) episodes
        freed: \(ByteCountFormatter.string(fromByteCount: freedBytes, countStyle: .file))
      """
    )
  }

  // MARK: - Dangling File Purge

  private func purgeDanglingFiles(cachedEpisodes: [Episode]) async throws {
    let cachedFiles = try podFileManager.contentsOfDirectory(at: CacheManager.cacheDirectory)

    let episodeCachedFilenames = Set(
      cachedEpisodes.compactMap { $0.cachedURL?.lastPathComponent }
    )

    // Find files that don't have a corresponding episode
    let danglingFiles = cachedFiles.filter { fileURL in
      !episodeCachedFilenames.contains(fileURL.lastPathComponent)
    }

    guard !danglingFiles.isEmpty else {
      Self.log.debug("no dangling files found")
      return
    }

    var freedBytes: Int64 = 0
    for fileURL in danglingFiles {
      do {
        let fileSize = try podFileManager.fileSize(for: fileURL)
        try podFileManager.removeItem(at: fileURL)
        freedBytes += fileSize
        Self.log.notice(
          """
          found and deleted dangling file: \(fileURL.lastPathComponent)
          freed: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
          """
        )
      } catch {
        Self.log.error(error)
      }
    }

    Self.log.debug(
      """
      dangling file purge completed: 
      freed \(ByteCountFormatter.string(fromByteCount: freedBytes, countStyle: .file))
      """
    )
  }

  // MARK: - Cached Episode Validation

  private func validateCachedEpisodes(cachedEpisodes: [Episode]) async throws {
    var clearedCount = 0

    for episode in cachedEpisodes {
      guard let cachedURL = episode.cachedURL else { continue }

      if !podFileManager.fileExists(at: cachedURL.rawValue) {
        try await repo.updateCachedFilename(episode.id, nil)
        clearedCount += 1
        Self.log.notice(
          """
          cleared cached filename for episode with missing file:
            episode: \(episode.toString)
            missing file: \(cachedURL.lastPathComponent)
          """
        )
      }
    }

    if clearedCount > 0 {
      Self.log.debug("validated cached episodes: cleared \(clearedCount) missing file(s)")
    } else {
      Self.log.debug("validated cached episodes: all files present")
    }
  }

  // MARK: - Cache Size Calculation

  private func calculateCacheSize() throws -> Int64 {
    let cachedFiles = try podFileManager.contentsOfDirectory(at: CacheManager.cacheDirectory)

    Self.log.trace(
      """
      Contents of cache directory are:
        \(cachedFiles.map(\.lastPathComponent).joined(separator: "\n  "))
      """
    )

    var totalSize: Int64 = 0
    for url in cachedFiles {
      totalSize += try podFileManager.fileSize(for: url)
    }

    return totalSize
  }

  // MARK: - Episode Deletion Heuristic

  private func getCachedEpisodesInDeletionOrder(cachedEpisodes: [Episode]) async throws
    -> [Episode]
  {
    let twoDaysAgo = Date.now.addingTimeInterval(-oldEpisodeThreshold.asTimeInterval)

    // Filter out queued episodes
    let unqueuedEpisodes = cachedEpisodes.filter { !$0.queued }

    // Separate into categories
    let oldPlayedEpisodes =
      unqueuedEpisodes.filter {
        $0.finished && ($0.completionDate ?? Date.distantPast) < twoDaysAgo
      }
      .sorted { ($0.completionDate ?? Date.distantPast) < ($1.completionDate ?? Date.distantPast) }

    let oldUnplayedEpisodes =
      unqueuedEpisodes.filter {
        !$0.finished && $0.pubDate < twoDaysAgo
      }
      .sorted { $0.pubDate < $1.pubDate }

    let recentEpisodes =
      unqueuedEpisodes.filter {
        guard $0.finished else {
          return $0.pubDate >= twoDaysAgo
        }
        return ($0.completionDate ?? Date.distantPast) >= twoDaysAgo
      }
      .sorted { $0.pubDate < $1.pubDate }

    // Combine in priority order
    return oldPlayedEpisodes + oldUnplayedEpisodes + recentEpisodes
  }
}
