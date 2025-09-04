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
  private static var session: FakeDataFetchable {
    Container.shared.cacheManagerSession() as! FakeDataFetchable
  }

  // MARK: - Queue Manipulation

  static func unshiftToActive(podcastEpisode: PodcastEpisode) async throws {
    try await queue.unshift(podcastEpisode.id)
    try await waitForDownloadTaskID(podcastEpisode.id)
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

  // MARK: - Data Generation

  static func createRandomData(size: Int = 1024) -> Data {
    var data = Data(capacity: size)
    for _ in 0..<size {
      data.append(UInt8.random(in: 0...255))
    }
    return data
  }

  static func readCachedFileData(_ fileName: String) async throws -> Data {
    let fileURL = CacheManager.resolveCachedFilepath(for: fileName)
    return try await fileManager.readData(from: fileURL)
  }

  // MARK: - Background Download Simulation

  static func simulateBackgroundFinish(_ episodeID: Episode.ID, data: Data) async throws {
    let taskID: DownloadTaskID = try await repo.episode(episodeID)!.downloadTaskID!

    // Write data to a temp location simulating the downloaded file
    let tmpURL = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try await fileManager.writeData(data, to: tmpURL)

    // Ask the fake background fetchable to complete by invoking the delegate
    await session.finishDownload(taskID: taskID, tmpURL: tmpURL)
  }

  static func simulateBackgroundFailure(
    _ episodeID: Episode.ID,
    error: Error = NSError(domain: "Test", code: -1)
  ) async throws {
    let taskID: DownloadTaskID = try await repo.episode(episodeID)!.downloadTaskID!

    // Invoke failure on the fake background session
    await session.failDownload(taskID: taskID, error: error)
  }
}
