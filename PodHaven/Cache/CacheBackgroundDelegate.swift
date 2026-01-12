// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Logging
import Synchronization
import Tagged
import UIKit

extension Container {
  var cacheBackgroundDelegate: Factory<CacheBackgroundDelegate> {
    Factory(self) { CacheBackgroundDelegate() }.scope(.cached)
  }
}

final class CacheBackgroundDelegate: NSObject, URLSessionDownloadDelegate {
  private var repo: any Databasing { Container.shared.repo() }
  private var cacheState: CacheState { get async { await Container.shared.cacheState() } }
  private var sleeper: any Sleepable { Container.shared.sleeper() }
  private var fileManager: any FileManaging { Container.shared.fileManager() }
  private var loadEpisodeAsset: (_ asset: AVURLAsset) async throws -> EpisodeAsset {
    Container.shared.loadEpisodeAsset()
  }

  private static let log = Log.as(LogSubsystem.Cache.backgroundDelegate)

  private let completions = ThreadSafe<[URLSessionConfiguration.ID: @MainActor () -> Void]>([:])

  // MARK: - Completion Management

  func store(id: URLSessionConfiguration.ID, completion: @escaping @MainActor () -> Void) {
    completions[id] = completion
  }

  func complete(for id: URLSessionConfiguration.ID) {
    let completion = completions { dict in
      dict.removeValue(forKey: id)
    }
    if let completion {
      Task { @MainActor in completion() }
    }
  }

  // MARK: - URLSessionDownloadDelegate

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    Task {
      await urlSession(
        session,
        downloadTask: downloadTask,
        didWriteData: bytesWritten,
        totalBytesWritten: totalBytesWritten,
        totalBytesExpectedToWrite: totalBytesExpectedToWrite
      )
    }
  }
  func urlSession(
    _ session: any DataFetchable,
    downloadTask: any DownloadingTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) async {
    guard totalBytesExpectedToWrite > 0 else { return }
    do {
      if let episode = try await repo.episode(downloadTask.taskID) {
        await cacheState.updateProgress(
          for: episode.id,
          progress: Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        )
      }
    } catch {
      Self.log.error(error)
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    let safeTempURL = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    do {
      try fileManager.moveItem(at: location, to: safeTempURL)
    } catch {
      Self.log.error(error)
      return
    }

    Task {
      await urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: safeTempURL)
    }
  }
  func urlSession(
    _ session: any DataFetchable,
    downloadTask: any DownloadingTask,
    didFinishDownloadingTo location: URL
  ) async {
    do {
      guard let episode = try await repo.episode(downloadTask.taskID) else {
        Self.log.debug("No episode for task #\(downloadTask.taskID)?")
        try fileManager.removeItem(at: location)
        return
      }

      try await repo.updateDownloadTaskID(episode.id, downloadTaskID: nil)
      await cacheState.clearProgress(for: episode.id)

      let fileName = generateCacheFilename(for: episode)
      let destURL = CacheManager.resolveCachedFilepath(for: fileName)
      if fileManager.fileExists(at: destURL.rawValue) {
        Self.log.notice("File already cached for \(episode.id) at \(destURL), removing")
        try fileManager.removeItem(at: destURL.rawValue)
      }

      try await repo.updateCachedFilename(episode.id, cachedFilename: fileName)
      do {
        try fileManager.moveItem(at: location, to: destURL.rawValue)
        let episodeAsset = try await loadEpisodeAsset(AVURLAsset(url: destURL.rawValue))

        guard episodeAsset.isPlayable
        else { throw CacheError.mediaNotPlayable(episode) }

        try await repo.updateDuration(episode.id, duration: episodeAsset.duration)
      } catch {
        try await repo.updateCachedFilename(episode.id, cachedFilename: nil)
        throw error
      }

      Self.log.debug("Cached episode \(episode.id) to \(fileName)")
    } catch {
      Self.log.error(error)
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    guard let downloadTask = task as? URLSessionDownloadTask
    else { Assert.fatal("didCompleteWithError passed non URLSessionDownloadTask? \(task)") }

    Task { await urlSession(session, task: downloadTask, didCompleteWithError: error) }
  }
  func urlSession(
    _ session: any DataFetchable,
    task: any DownloadingTask,
    didCompleteWithError error: (any Error)?
  ) async {
    guard error != nil else { return }

    do {
      guard let episode = try await repo.episode(task.taskID) else {
        Self.log.warning("No episode for task #\(task.taskID)?")
        return
      }

      await cacheState.clearProgress(for: episode.id)
      try await repo.updateDownloadTaskID(episode.id, downloadTaskID: nil)
      Self.log.notice("Episode \(episode.toString) completed with error")
    } catch {
      Self.log.error(error)
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    guard let id = session.configuration.identifier else { return }
    complete(for: URLSessionConfiguration.ID(id))
  }

  // MARK: - Private Helpers

  private func generateCacheFilename(for episode: Episode) -> String {
    let mediaURL = episode.mediaURL.rawValue
    let fileExtension =
      mediaURL.pathExtension.isEmpty == false
      ? mediaURL.pathExtension
      : "mp3"
    return "\(mediaURL.hash(to: 12)).\(fileExtension)"
  }
}
