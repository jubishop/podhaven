// Copyright Justin Bishop, 2025

import Algorithms
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

  let cacheSizeLimit: Int64 = 1024 * 1024 * 1024  // 1GB
  private let cadence: Duration = .hours(12)

  // MARK: - State Management

  private let purgeLock = ThreadLock()
  private let backgroundTaskScheduler: BackgroundTaskScheduler

  // MARK: - Initialization

  fileprivate init() {
    self.backgroundTaskScheduler = BackgroundTaskScheduler(
      identifier: Self.backgroundTaskIdentifier,
      cadence: cadence
    )
  }

  func start() {
    guard Function.neverCalled() else { return }

    Self.log.debug("start: executing")

    backgroundTaskScheduler.scheduleNext(in: cadence)
  }

  // MARK: - Background Task

  func register() {
    backgroundTaskScheduler.register { [weak self] complete in
      guard let self
      else {
        complete(false)
        return
      }

      do {
        try await executePurge()
        try Task.checkCancellation()
        complete(true)
      } catch {
        Self.log.error(error)
        complete(false)
      }
    }
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

    var freedBytes: Int64 = 0
    var deletedCount = 0

    for episode in try await getCachedEpisodesInDeletionOrder(cachedEpisodes: cachedEpisodes) {
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
    let episodeCachedFilenames = Set(cachedEpisodes.compactMap { $0.cachedURL?.lastPathComponent })

    for cachedFile in cachedFiles
    where !episodeCachedFilenames.contains(cachedFile.lastPathComponent) {
      do {
        try podFileManager.removeItem(at: cachedFile)
        Self.log.notice("found and deleted dangling file: \(cachedFile.lastPathComponent)")
      } catch {
        Self.log.error(error)
      }
    }
  }

  // MARK: - Cached Episode Validation

  private func validateCachedEpisodes(cachedEpisodes: [Episode]) async throws {
    for episode in cachedEpisodes {
      guard let cachedURL = episode.cachedURL else { continue }
      guard !podFileManager.fileExists(at: cachedURL.rawValue) else { continue }

      try await repo.updateCachedFilename(episode.id, nil)
      Self.log.notice(
        """
        cleared cached filename for episode with missing file:
          episode: \(episode.toString)
          missing file: \(cachedURL.lastPathComponent)
        """
      )
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
    let unqueuedEpisodes = cachedEpisodes.filter { !$0.queued }
    var (uncompletedEpisodes, completedEpisodes) = unqueuedEpisodes.partitioned(by: \.finished)
    completedEpisodes.sort { lhs, rhs in
      let lhsDate = lhs.completionDate ?? .distantPast
      let rhsDate = rhs.completionDate ?? .distantPast

      return lhsDate < rhsDate
    }
    uncompletedEpisodes.sort { lhs, rhs in lhs.pubDate < rhs.pubDate }
    return completedEpisodes + uncompletedEpisodes
  }
}
