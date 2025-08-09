// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

enum CacheHelpers {
  // MARK: - Dependency Access

  private static var appDB: AppDB { Container.shared.appDB() }
  private static var cacheManager: CacheManager { Container.shared.cacheManager() }
  private static var downloadManager: DownloadManager { Container.shared.cacheDownloadManager() }
  private static var queue: any Queueing { Container.shared.queue() }
  private static var repo: any Databasing { Container.shared.repo() }

  private static var session: FakeDataFetchable {
    Container.shared.cacheManagerSession() as! FakeDataFetchable
  }

  // MARK: - Episode Status

  @discardableResult
  static func waitForCached(_ episodeID: Episode.ID) async throws -> String {
    try await Wait.forValue(
      {
        let episode: Episode? = try await repo.episode(episodeID)
        return episode?.cachedFilename
      }
    )
  }

  static func waitForNotCached(_ episodeID: Episode.ID) async throws {
    try await Wait.until(
      {
        let episode: Episode? = try await repo.episode(episodeID)
        return episode?.cachedFilename == nil
      },
      { "Episode \(episodeID) cachedFilename is not nil" }
    )
  }

  // MARK: - Download Status

  static func waitForActiveDownloadTask(_ episodeID: Episode.ID) async throws {
    try await Wait.until(
      { await self.cacheManager.activeDownloadTasks[episodeID] != nil },
      { "Expected episode id: \(episodeID) to be in active downloads" }
    )
  }

  static func waitForNotActiveDownloadTask(_ episodeID: Episode.ID) async throws {
    try await Wait.until(
      { await self.cacheManager.activeDownloadTasks[episodeID] == nil },
      { "Expected episode id: \(episodeID) to not be in active downloads" }
    )
  }

  static func waitForTopPendingDownload(_ url: URL) async throws {
    try await Wait.until(
      { await self.downloadManager.pendingDownloads.first?.url == url },
      { "Expected episode url: \(url.hash()) to be the first pending download" }
    )
  }

  // MARK: - File Status

  static func waitForCachedFile(_ fileName: String) async throws {
    try await Wait.until(
      {
        let fileURL = CacheManager.resolveCachedFilepath(for: fileName)
        return FileManager.default.fileExists(atPath: fileURL.path)
      },
      { "Cached file: \(fileName) does not exist on disk" }
    )
  }

  static func waitForCachedFileRemoved(_ fileName: String) async throws {
    try await Wait.until(
      {
        let fileURL = CacheManager.resolveCachedFilepath(for: fileName)
        return !FileManager.default.fileExists(atPath: fileURL.path)
      },
      { "Cached file: \(fileName) still exists on disk" }
    )
  }

  // MARK: - Data Generation

  static func createRandomData(size: Int = 1024) -> Data {
    var data = Data(capacity: size)
    for _ in 0..<size {
      data.append(UInt8.random(in: 0...255))
    }
    return data
  }
}
