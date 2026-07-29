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
  private var cacheFileStore: CacheFileStore { Container.shared.cacheFileStore() }
  private var cacheManager: CacheManager { Container.shared.cacheManager() }
  private var fileManager: any FileManaging { Container.shared.fileManager() }
  private var repo: any Databasing { Container.shared.repo() }
  private var transcriptionQueue: TranscriptionQueue { Container.shared.transcriptionQueue() }
  private var userSettings: UserSettings { Container.shared.userSettings() }

  private static let backgroundTaskIdentifier = "\(AppInfo.bundleIdentifier).cachePurge"

  private static let log = Log.as(LogSubsystem.Cache.purger)

  // MARK: - Configuration

  var cacheSizeLimit: Int64 {
    Int64(userSettings.cacheSizeLimitGB * 1024 * 1024 * 1024)
  }
  private let cadence: Duration = .hours(12)

  // MARK: - State Management

  private let purgeLock = ThreadLock()
  private let backgroundTaskScheduler: BackgroundTaskScheduler

  // MARK: - Initialization

  fileprivate init() {
    self.backgroundTaskScheduler = BackgroundTaskScheduler(
      identifier: Self.backgroundTaskIdentifier,
      cadence: cadence,
      taskType: .processing(requiresNetworkConnectivity: false)
    )
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
        Self.log.caughtError("register: background cache purge failed", error)
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

    let cachedEpisodes = try await repo.cachedEpisodes()

    try await purgeDanglingFiles(cachedEpisodes: cachedEpisodes)
    await validateCachedEpisodes(cachedEpisodes: cachedEpisodes)

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
    var releasedCount = 0
    var removedFileCount = 0

    for episode in getCachedEpisodesInDeletionOrder(cachedEpisodes: cachedEpisodes) {
      guard freedBytes < bytesToFree else { break }

      if let cachedURL = episode.cachedURL {
        let fileSize: Int64
        do {
          fileSize = try fileManager.fileSize(for: cachedURL.rawValue)
        } catch {
          if ErrorKit.isMissingFile(error) {
            Self.log.caughtError(
              "executePurge: cached file already missing for \(cachedURL) (\(episode.toString))",
              error,
              level: .debug
            )
            continue
          }

          Self.log.caughtError(
            "executePurge: failed to get file size for \(cachedURL) (\(episode.toString))",
            error
          )
          continue
        }

        do {
          if let disposition = try await cacheManager.clearCache(for: episode.id) {
            releasedCount += 1
            switch disposition {
            case .retained(let cachedURL):
              Self.log.debug(
                """
                  released: \(episode.toString)
                  retained shared file: \(cachedURL.lastPathComponent)
                """
              )
            case .removed(let cachedURL):
              freedBytes += fileSize
              removedFileCount += 1
              Self.log.debug(
                """
                  released: \(episode.toString)
                  deleted file: \(cachedURL.lastPathComponent)
                  bytes: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                """
              )
            case .alreadyMissing:
              break
            }
          }
        } catch {
          Self.log.caughtError(
            "executePurge: failed to clear cache for \(episode.toString)",
            error
          )
        }
      }
    }

    Self.log.debug(
      """
      purge completed:
        released: \(releasedCount) episode references
        deleted: \(removedFileCount) files
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
        let disposition = try await cacheFileStore.removeFileIfUnreferenced(
          CachedURL(cachedFile)
        )
        switch disposition {
        case .retained:
          Self.log.debug(
            "retained newly referenced cache file: \(cachedFile.lastPathComponent)"
          )
        case .removed:
          Self.log.notice("found and deleted dangling file: \(cachedFile.lastPathComponent)")
        case .alreadyMissing:
          Self.log.debug("dangling file already missing: \(cachedFile.lastPathComponent)")
        }
      } catch {
        Self.log.caughtError(
          "purgeDanglingFiles: failed to remove dangling file \(cachedFile.lastPathComponent)",
          error
        )
      }
    }
  }

  // MARK: - Cached Episode Validation

  private func validateCachedEpisodes(cachedEpisodes: [Episode]) async {
    for episode in cachedEpisodes {
      guard let cachedURL = episode.cachedURL else { continue }
      guard !fileManager.fileExists(at: cachedURL.rawValue) else { continue }

      do {
        try await repo.updateCachedFilename(episode.id, cachedFilename: nil)
        Self.log.notice(
          """
          cleared cached filename for episode with missing file:
            episode: \(episode.toString)
            missing file: \(cachedURL.lastPathComponent)
          """
        )
      } catch {
        Self.log.caughtError(
          "validateCachedEpisodes: failed to clear cached filename for \(episode.toString)",
          error
        )
        continue
      }

      if episode.queued {
        do {
          try await cacheManager.downloadToCache(for: episode.id)
          Self.log.notice(
            "re-queued download for queued episode with missing cache: \(episode.toString)"
          )
        } catch {
          Self.log.caughtError(
            "validateCachedEpisodes: failed to re-queue download for \(episode.toString)",
            error
          )
        }
      }
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

    var totalSize: Int64 = 0
    for cachedFile in cachedFiles {
      do {
        totalSize += try fileManager.fileSize(for: cachedFile)
      } catch {
        guard ErrorKit.isMissingFile(error) else { throw error }
        Self.log.caughtError(
          "calculateCacheSize: cached file already missing for \(cachedFile.lastPathComponent)",
          error,
          level: .debug
        )
      }
    }

    return totalSize
  }

  // MARK: - Episode Deletion Heuristic

  private func getCachedEpisodesInDeletionOrder(cachedEpisodes: [Episode]) -> [Episode] {
    let currentEpisodeID = Container.shared.sharedState().$currentEpisodeID.value
    let transcribingEpisodeIDs = Set(transcriptionQueue.progress.keys)
    let unqueuedEpisodes = cachedEpisodes.filter {
      !$0.queued && !$0.saveInCache && $0.id != currentEpisodeID
        && !transcribingEpisodeIDs.contains($0.id)
    }
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
      Self.log.debug("activated")
    case .background:
      Self.log.debug("backgrounded")

      backgroundTaskScheduler.scheduleNext()
    default:
      break
    }
  }
}
