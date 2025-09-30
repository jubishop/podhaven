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
  private var repo: any Databasing { Container.shared.repo() }

  private static let backgroundTaskIdentifier = "com.justinbishop.podhaven.cachePurge"

  private static let log = Log.as(LogSubsystem.Cache.purger)

  // MARK: - Configuration

  private let cacheSizeLimit: Int64 = 500 * 1024 * 1024  // 500 MB
  private let cadence: Duration = .hours(6)
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

    let cacheDirectory = CacheManager.cacheDirectory

    // Calculate total cache size
    let totalSize = try calculateCacheSize(at: cacheDirectory)
    Self.log.debug(
      "current cache size: \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))"
    )

    guard totalSize > cacheSizeLimit else {
      Self.log.debug("cache size within limit, no purge needed")
      return
    }

    let bytesToFree = totalSize - cacheSizeLimit
    Self.log.debug(
      "need to free: \(ByteCountFormatter.string(fromByteCount: bytesToFree, countStyle: .file))"
    )

    // Get cached episodes in deletion priority order
    let episodesToDelete = try await getCachedEpisodesInDeletionOrder()

    var freedBytes: Int64 = 0
    var deletedCount = 0

    for episode in episodesToDelete {
      guard freedBytes < bytesToFree else { break }

      if let cachedURL = episode.cachedURL {
        let fileSize = try getFileSize(at: cachedURL.rawValue)

        do {
          if let clearedURL = try await cacheManager.clearCache(for: episode.id) {
            freedBytes += fileSize
            deletedCount += 1
            Self.log.debug(
              """
                deleted: \(episode.toString)
                cached file: \(clearedURL).
                bytes: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
              """
            )
          }
        } catch {
          Self.log.error("failed to delete \(episode.toString): \(error)")
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

  // MARK: - Cache Size Calculation

  private func calculateCacheSize(at directory: URL) throws -> Int64 {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: directory.path) else { return 0 }

    let contents = try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.fileSizeKey],
      options: .skipsHiddenFiles
    )

    var totalSize: Int64 = 0
    for url in contents {
      totalSize += try getFileSize(at: url)
    }

    return totalSize
  }

  private func getFileSize(at url: URL) throws -> Int64 {
    let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
    return Int64(resourceValues.fileSize ?? 0)
  }

  // MARK: - Episode Deletion Heuristic

  private func getCachedEpisodesInDeletionOrder() async throws -> [Episode] {
    let twoDaysAgo = Date.now.addingTimeInterval(-oldEpisodeThreshold.asTimeInterval)

    // Get all cached episodes that are not queued
    let cachedEpisodes = try await repo.unqueuedCachedEpisodes()

    // Separate into categories
    let oldPlayedEpisodes =
      cachedEpisodes.filter {
        $0.finished && ($0.completionDate ?? Date.distantPast) < twoDaysAgo
      }
      .sorted { ($0.completionDate ?? Date.distantPast) < ($1.completionDate ?? Date.distantPast) }

    let oldUnplayedEpisodes =
      cachedEpisodes.filter {
        !$0.finished && $0.pubDate < twoDaysAgo
      }
      .sorted { $0.pubDate < $1.pubDate }

    let recentEpisodes =
      cachedEpisodes.filter {
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
