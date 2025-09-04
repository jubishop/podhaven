// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import Synchronization
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
  private var podFileManager: any FileManageable { Container.shared.podFileManager() }

  private static let log = Log.as("CacheBackgroundDelegate")

  private let completions = Mutex<[String: @MainActor () -> Void]>([:])

  func handleDidFinish(taskID: DownloadTaskID, location: URL) async {
    do {
      guard let episode = try await repo.episode(taskID) else {
        Self.log.warning("handleDidFinish: No episode for task #\(taskID)")
        return
      }

      if episode.queued == false {
        Self.log.debug("Episode dequeued mid-download; skipping cache move for \(episode.id)")
        try await podFileManager.removeItem(at: location)
        try await repo.updateDownloadTaskID(episode.id, nil)
        return
      }

      let fileName = CacheManager.generateCacheFilename(for: episode)
      let destURL = CacheManager.resolveCachedFilepath(for: fileName)
      if await podFileManager.fileExists(at: destURL) {
        try await podFileManager.removeItem(at: destURL)
      }
      let data = try await podFileManager.readData(from: location)
      try await podFileManager.writeData(data, to: destURL)
      try await podFileManager.removeItem(at: location)
      try await repo.updateCachedFilename(episode.id, fileName)
      try await repo.updateDownloadTaskID(episode.id, nil)
      Self.log.debug("Cached episode \(episode.id) to \(fileName)")
    } catch {
      Self.log.error(error)
    }
  }

  func handleDidComplete(taskID: DownloadTaskID, error: Error) async {
    do {
      if let episode = try await repo.episode(taskID) {
        try await repo.updateDownloadTaskID(episode.id, nil)
        Self.log.debug("Episode \(episode.toString) did complete")
      } else {
        Self.log.warning("taskID: \(taskID) has no episode associated")
      }
    } catch {
      Self.log.error(error)
    }
  }

  // MARK: - Completion Management

  func store(identifier: String?, completion: @escaping @MainActor () -> Void) {
    guard let id = identifier else { return }
    completions.withLock { dict in
      dict[id] = completion
    }
  }

  func complete(for identifier: String?) {
    guard let id = identifier else { return }
    let completion = completions.withLock { dict in
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
    guard totalBytesExpectedToWrite > 0 else { return }
    Task {
      await urlSession(
        downloadTask: downloadTask,
        totalBytesWritten: totalBytesWritten,
        totalBytesExpectedToWrite: totalBytesExpectedToWrite
      )
    }
  }
  func urlSession(
    downloadTask: any DownloadingTask,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) async {
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
    Task { await handleDidFinish(taskID: downloadTask.taskID, location: location) }
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
    complete(for: session.configuration.identifier)
  }
}
