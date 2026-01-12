// Copyright Justin Bishop, 2025

import Algorithms
import BackgroundTasks
import ConcurrencyExtras
import FactoryKit
import Foundation
import Logging
import SwiftUI
import Tagged

extension Container {
  var cachePurger: Factory<CachePurger> {
    Factory(self) { CachePurger() }.scope(.cached)
  }
}

struct CachePurger: Sendable {
  private var cacheManager: CacheManager { Container.shared.cacheManager() }
  private var fileManager: any FileManaging { Container.shared.fileManager() }
  private var repo: any Databasing { Container.shared.repo() }
  private var userSettings: UserSettings { Container.shared.userSettings() }

  private static let backgroundTaskIdentifier = "com.artisanalsoftware.podhaven.purgeCache"

  private static let log = Log.as(LogSubsystem.Cache.purger)

  // MARK: - Configuration

  var cacheSizeLimit: Int64 {
    Int64(userSettings.cacheSizeLimitGB * 1024 * 1024 * 1024)
  }
  private let cadence: Duration = .hours(1)

  // MARK: - State Management

  private let purgeLock = ThreadLock()
  private let backgroundTaskScheduler: BackgroundTaskScheduler

  // MARK: - Initialization

  fileprivate init() {
    self.backgroundTaskScheduler = BackgroundTaskScheduler(
      identifier: Self.backgroundTaskIdentifier,
      cadence: cadence,
      taskType: .processing
    )
  }

  func start() {
    guard Function.neverCalled() else { return }

    Self.log.debug("start: executing")

    backgroundTaskScheduler.scheduleNext(in: cadence)
  }

  // MARK: - Background Task

  func register() {
    Self.log.debug("registering")

    backgroundTaskScheduler.register { complete in
      do {
        Self.log.debug("background cache purge: performing purge")

        try await executePurge()
        try Task.checkCancellation()

        Self.log.debug("background cache purge: completed gracefully")

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
          let fileSize = try fileManager.fileSize(for: cachedURL.rawValue)
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
    let cachedFiles = try fileManager.contentsOfDirectory(at: CacheManager.cacheDirectory)
    let episodeCachedFilenames = Set(cachedEpisodes.compactMap { $0.cachedURL?.lastPathComponent })

    for cachedFile in cachedFiles
    where !episodeCachedFilenames.contains(cachedFile.lastPathComponent) {
      do {
        try fileManager.removeItem(at: cachedFile)
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
      guard !fileManager.fileExists(at: cachedURL.rawValue) else { continue }

      try await repo.updateCachedFilename(episode.id, cachedFilename: nil)
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
    let cachedFiles = try fileManager.contentsOfDirectory(at: CacheManager.cacheDirectory)
    Self.log.trace(
      """
      Contents of cache directory are:
        \(cachedFiles.map(\.lastPathComponent).joined(separator: "\n  "))
      """
    )

    return try cachedFiles.reduce(into: 0) { $0 += try fileManager.fileSize(for: $1) }
  }

  // MARK: - Episode Deletion Heuristic

  private func getCachedEpisodesInDeletionOrder(cachedEpisodes: [Episode]) async throws
    -> [Episode]
  {
    let unqueuedEpisodes = cachedEpisodes.filter { !$0.queued && !$0.saveInCache }
    var (unfinishedEpisodes, finishedEpisodes) = unqueuedEpisodes.partitioned(by: \.finished)
    finishedEpisodes.sort { lhs, rhs in
      let lhsDate = lhs.finishDate ?? .distantPast
      let rhsDate = rhs.finishDate ?? .distantPast

      return lhsDate < rhsDate
    }
    unfinishedEpisodes.sort { lhs, rhs in lhs.pubDate < rhs.pubDate }
    return finishedEpisodes + unfinishedEpisodes
  }

  // MARK: - Phase Changes

  func handleScenePhaseChange(to scenePhase: ScenePhase) {
    switch scenePhase {
    case .active:
      break
    case .background:
      Self.log.debug("backgrounded")

      backgroundTaskScheduler.scheduleNext(in: cadence)
    default:
      break
    }
  }
}
