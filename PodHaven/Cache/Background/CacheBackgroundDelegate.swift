// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import UIKit

// MARK: - CacheBackgroundDelegate

final class CacheBackgroundDelegate: NSObject, URLSessionDownloadDelegate {
  private var repo: any Databasing { Container.shared.repo() }
  private var cacheState: CacheState { get async { await Container.shared.cacheState() } }
  private var sleeper: any Sleepable { Container.shared.sleeper() }
  private var taskMapStore: TaskMapStore { Container.shared.taskMapStore() }
  private var podFileManager: any FileManageable { Container.shared.podFileManager() }

  private static let log = Log.as("CacheBackgroundDelegate")

  // These internal helpers are used by the delegate to reuse logic.
  func handleDidFinish(taskID: DownloadTaskID, location: URL) async {
    defer { Task { await taskMapStore.remove(taskID: taskID) } }

    guard let mg = await taskMapStore.key(for: taskID) else {
      Self.log.warning("handleDidFinish: No mapping for task \(taskID)")
      return
    }

    do {
      guard let episode = try await repo.episode(mg) else {
        Self.log.warning("Episode not found for guid: \(mg)")
        return
      }

      if episode.queued == false {
        Self.log.debug("Episode dequeued mid-download; skipping cache move for \(episode.id)")
        try? await podFileManager.removeItem(at: location)
        await cacheState.markFinished(episode.id)
        return
      }

      let fileName = CacheManager.generateCacheFilename(for: episode)
      let destURL = CacheManager.resolveCachedFilepath(for: fileName)
      if await podFileManager.fileExists(at: destURL) {
        try? await podFileManager.removeItem(at: destURL)
      }
      let data = try await podFileManager.readData(from: location)
      try await podFileManager.writeData(data, to: destURL)
      try? await podFileManager.removeItem(at: location)
      _ = try await repo.updateCachedFilename(episode.id, fileName)

      await cacheState.markFinished(episode.id)
      Self.log.debug("Cached episode \(episode.id) to \(fileName)")
    } catch {
      Self.log.error(error)
    }
  }

  func handleDidComplete(taskID: DownloadTaskID, error: Error) async {
    if let mg = await taskMapStore.key(for: taskID) {
      do {
        if let episode = try await repo.episode(mg) {
          await cacheState.markFailed(episode.id, error: error)
        }
      } catch {
        Self.log.error(error)
      }
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
    guard totalBytesExpectedToWrite > 0 else { return }
    let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    Task { [progress] in
      if let mg = await taskMapStore.key(for: downloadTask.taskID) {
        await cacheState.updateProgress(for: mg, progress: progress)
      }
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    Task {
      await handleDidFinish(taskID: downloadTask.taskID, location: location)
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let error else { return }
    guard let downloadTask = task as? URLSessionDownloadTask else { return }
    Task { await handleDidComplete(taskID: downloadTask.taskID, error: error) }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    Container.shared.backgroundURLSessionCompletionCenter()
      .complete(for: session.configuration.identifier)
  }
}

// MARK: - DI

extension Container {
  var cacheBackgroundDelegate: Factory<CacheBackgroundDelegate> {
    Factory(self) { CacheBackgroundDelegate() }.scope(.cached)
  }
}
