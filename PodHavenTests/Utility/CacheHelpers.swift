// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

enum CacheHelpers {
  private static var cacheManager: CacheManager { Container.shared.cacheManager() }
  private static var cacheBackgroundDelegate: CacheBackgroundDelegate {
    Container.shared.cacheBackgroundDelegate()
  }
  private static var cacheState: CacheState { get async { await Container.shared.cacheState() } }
  private static var queue: any Queueing { Container.shared.queue() }
  private static var repo: any Databasing { Container.shared.repo() }

  private static var fileManager: any FileManageable {
    Container.shared.podFileManager() as! FakeFileManager
  }
  private static var imageFetcher: FakeImageFetcher {
    Container.shared.imageFetcher() as! FakeImageFetcher
  }
  private static var session: FakeDataFetchable {
    Container.shared.cacheManagerSession() as! FakeDataFetchable
  }

  // MARK: - Queue Manipulation

  @discardableResult
  static func unshiftToQueue(_ episodeID: Episode.ID) async throws -> DownloadTaskID {
    try await queue.unshift(episodeID)
    let taskID = try await waitForDownloadTaskID(episodeID)
    try await waitForResumed(taskID)
    return taskID
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

  @discardableResult
  static func waitForDownloadTaskID(_ episodeID: Episode.ID) async throws -> DownloadTaskID {
    try await Wait.forValue(
      {
        let episode: Episode? = try await repo.episode(episodeID)
        return episode?.downloadTaskID
      }
    )
  }

  static func waitForNoDownloadTaskID(_ episodeID: Episode.ID) async throws {
    try await Wait.until(
      {
        let episode: Episode? = try await repo.episode(episodeID)
        return episode?.downloadTaskID == nil
      },
      { "Episode \(episodeID) downloadTaskID is not nil" }
    )
  }

  // MARK: - Task Status

  static func waitForResumed(_ taskID: DownloadTaskID) async throws {
    try await Wait.until(
      {
        await session.downloadTasks[id: taskID]?.isResumed == true
      },
      { "Task \(taskID) is not resumed" }
    )
  }

  static func waitForCancelled(_ taskID: DownloadTaskID) async throws {
    try await Wait.until(
      {
        await session.downloadTasks[id: taskID]?.isCancelled == true
      },
      { "Task \(taskID) is not cancelled" }
    )
  }

  // MARK: - Progress Status

  static func waitForProgress(_ episodeID: Episode.ID, progress: Double?) async throws {
    try await Wait.until(
      { await cacheState.progress(episodeID) == progress },
      { "Progress for Episode \(episodeID) never become \(String(describing: progress))" }
    )
  }

  // MARK: - File Status

  static func waitForCachedFile(_ fileName: String) async throws {
    try await Wait.until(
      {
        let fileURL = CacheManager.resolveCachedFilepath(for: fileName)
        return await fileManager.fileExists(at: fileURL)
      },
      { "Cached file: \(fileName) does not exist on disk" }
    )
  }

  static func waitForCachedFileRemoved(_ fileName: String) async throws {
    try await Wait.until(
      {
        let fileURL = CacheManager.resolveCachedFilepath(for: fileName)
        return await !fileManager.fileExists(at: fileURL)
      },
      { "Cached file: \(fileName) still exists on disk" }
    )
  }

  // MARK: - Image Prefetching

  static func waitForImagePrefetched(_ imageURL: URL) async throws {
    try await Wait.until(
      { await imageFetcher.prefetchCounts[imageURL] == 1 },
      { "ImageURL: \(imageURL) was not prefetched" }
    )
  }

  // MARK: - Data Generation

  static func cachedFileData(for fileName: String) async throws -> Data {
    let fileURL = CacheManager.resolveCachedFilepath(for: fileName)
    return try await fileManager.readData(from: fileURL)
  }

  // MARK: - Background Download Simulation

  static func simulateBackgroundFinish(_ episodeID: Episode.ID, data: Data = Data.random())
    async throws
  {
    // Write data to a temp location simulating the file being downloaded
    let tmpURL = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try await fileManager.writeData(data, to: tmpURL)

    await session.finishDownload(
      taskID: try await repo.episode(episodeID)!.downloadTaskID!,
      didFinishDownloadingTo: tmpURL
    )
  }

  static func simulateBackgroundFailure(
    _ episodeID: Episode.ID,
    error: Error = NSError(domain: "Test", code: -1)
  ) async throws {
    await session.failDownload(
      taskID: try await repo.episode(episodeID)!.downloadTaskID!,
      error: error
    )
  }
}
