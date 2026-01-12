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
  private static var dataLoader: FakeDataLoader { Container.shared.fakeDataLoader() }
  private static var queue: any Queueing { Container.shared.queue() }
  private static var repo: any Databasing { Container.shared.repo() }

  private static var fileManager: FakeFileManager {
    Container.shared.fileManager() as! FakeFileManager
  }
  private static var session: FakeDataFetchable {
    Container.shared.cacheManagerSession() as! FakeDataFetchable
  }

  // MARK: - Queue Manipulation

  @discardableResult
  static func unshiftToQueue(_ episodeID: Episode.ID) async throws -> URLSessionDownloadTask.ID {
    try await queue.unshift(episodeID)
    let taskID = try await waitForDownloadTaskID(episodeID)
    try await waitForResumed(taskID)
    return taskID
  }

  // MARK: - CacheManager Functions

  @discardableResult
  static func downloadToCache(_ episodeID: Episode.ID) async throws -> URLSessionDownloadTask.ID {
    let taskID = try await cacheManager.downloadToCache(for: episodeID)!
    try await waitForResumed(taskID)
    try await waitForDownloadTaskID(episodeID, taskID: taskID)
    return taskID
  }

  // MARK: - Episode Status

  @discardableResult
  static func waitForCached(_ episodeID: Episode.ID) async throws -> CachedURL {
    try await Wait.forValue(
      {
        let episode: Episode = try await repo.episode(episodeID)!
        return episode.cachedURL
      }
    )
  }

  static func waitForNotCached(_ episodeID: Episode.ID) async throws {
    try await Wait.until(
      {
        let episode: Episode = try await repo.episode(episodeID)!
        return episode.cacheStatus != .cached
      },
      { "Episode \(episodeID) is still cached" }
    )
  }

  @discardableResult
  static func waitForDownloadTaskID(_ episodeID: Episode.ID) async throws
    -> URLSessionDownloadTask.ID
  {
    try await Wait.forValue(
      {
        let episode: Episode = try await repo.episode(episodeID)!
        return episode.downloadTaskID
      }
    )
  }

  static func waitForDownloadTaskID(_ episodeID: Episode.ID, taskID: URLSessionDownloadTask.ID)
    async throws
  {
    try await Wait.until(
      { try await repo.episode(episodeID)!.downloadTaskID == taskID },
      {
        let episode = try await repo.episode(episodeID)!
        return
          """
          Expected episode \(episode.toString) downloadTaskID: \(taskID), 
          but got \(String(describing: episode.downloadTaskID)))
          """
      }
    )
  }

  static func waitForNoDownloadTaskID(_ episodeID: Episode.ID) async throws {
    try await Wait.until(
      {
        let episode: Episode = try await repo.episode(episodeID)!
        return episode.downloadTaskID == nil
      },
      { "Episode \(episodeID) downloadTaskID is not nil" }
    )
  }

  // MARK: - Task Status

  static func waitForResumed(_ taskID: URLSessionDownloadTask.ID) async throws {
    try await Wait.until(
      {
        await session.downloadTasks()[id: taskID]?.isResumed == true
      },
      { "Task \(taskID) is not resumed" }
    )
  }

  static func waitForCancelled(_ taskID: URLSessionDownloadTask.ID) async throws {
    try await Wait.until(
      { await session.downloadTasks()[id: taskID]?.isCancelled == true },
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

  static func waitForCachedFile(_ cachedURL: CachedURL) async throws {
    try await Wait.until(
      { fileManager.fileExists(at: cachedURL.rawValue) },
      { "Cached file: \(cachedURL) does not exist on disk" }
    )
  }

  static func waitForCachedFileRemoved(_ cachedURL: CachedURL) async throws {
    try await Wait.until(
      { !fileManager.fileExists(at: cachedURL.rawValue) },
      { "Cached file: \(cachedURL) still exists on disk" }
    )
  }

  static func waitForFileRemoved(_ fileURL: URL) async throws {
    try await Wait.until(
      { !fileManager.fileExists(at: fileURL) },
      { "File: \(fileURL) still exists on disk" }
    )
  }

  // MARK: - Image Fetching

  static func waitForImageFetched(_ imageURL: URL) async throws {
    try await Wait.until(
      { dataLoader.loadedURLs { set in set.contains(imageURL) } },
      { "ImageURL: \(imageURL) was not fetched" }
    )
  }

  // MARK: - Data Generation

  static func cachedFileData(for cachedURL: CachedURL) async throws -> Data {
    try await fileManager.readData(from: cachedURL.rawValue)
  }

  static func createCachedEpisode(
    title: String,
    cachedFilename: String,
    dataSize: Int = 1024 * 1024,  // 1 MB default
    finishDate: Date? = nil,
    pubDate: Date? = nil,
    saveInCache: Bool = false
  ) async throws -> Episode {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(
      title: title,
      pubDate: pubDate,
      finishDate: finishDate,
      cachedFilename: cachedFilename,
      saveInCache: saveInCache
    )

    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast, unsavedEpisodes: [unsavedEpisode])
    )

    let episode = podcastSeries.episodes.first!

    // Write fake file to simulate cached episode
    if let cachedURL = episode.cachedURL {
      let data = Data(count: dataSize)
      try await fileManager.writeData(data, to: cachedURL.rawValue)
    }

    return episode
  }

  // MARK: - Background Download Simulation

  @discardableResult
  static func simulateBackgroundFinish(
    _ taskID: URLSessionDownloadTask.ID,
    data: Data = Data.random()
  ) async throws -> URL {
    let fileURL = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try await fileManager.writeData(data, to: fileURL)

    await session.finishDownload(
      taskID: taskID,
      didFinishDownloadingTo: fileURL
    )

    return fileURL
  }

  static func simulateBackgroundFailure(
    _ taskID: URLSessionDownloadTask.ID,
    error: Error = NSError(domain: "Test", code: -1)
  ) async throws {
    await session.failDownload(
      taskID: taskID,
      error: error
    )
  }
}
