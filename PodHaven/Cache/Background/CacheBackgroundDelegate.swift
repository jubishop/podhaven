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

  private let completions = ThreadSafe<[URLSessionConfiguration.ID: @MainActor () -> Void]>([:])

  // MARK: - Completion Management

  func store(id: URLSessionConfiguration.ID, completion: @escaping @MainActor () -> Void) {
    completions { dict in
      dict[id] = completion
    }
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
      try podFileManager.moveItem(at: location, to: safeTempURL)
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
        try podFileManager.removeItem(at: location)
        return
      }

      await cacheState.clearProgress(for: episode.id)
      try await repo.updateDownloadTaskID(episode.id, nil)

      let fileName = CacheManager.generateCacheFilename(for: episode)
      let destURL = CacheManager.resolveCachedFilepath(for: fileName)
      if podFileManager.fileExists(at: destURL.rawValue) {
        Self.log.notice("File already cached for \(episode.id) at \(destURL), removing")
        try podFileManager.removeItem(at: destURL.rawValue)
      }

      try podFileManager.moveItem(at: location, to: destURL.rawValue)
      try await repo.updateCachedFilename(episode.id, fileName)
      Self.log.debug("Cached episode \(episode.id) to \(fileName)")
    } catch {
      Self.log.error(error)
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let downloadTask = task as? URLSessionDownloadTask
    else { Assert.fatal("didCompleteWithError passed non URLSessionDownloadTask? \(task)") }

    Task { await urlSession(session, task: downloadTask, didCompleteWithError: error) }
  }
  func urlSession(
    _ session: any DataFetchable,
    task: any DownloadingTask,
    didCompleteWithError error: Error?
  ) async {
    guard error != nil else { return }

    do {
      guard let episode = try await repo.episode(task.taskID) else {
        Self.log.debug("No episode for task #\(task.taskID)?")
        return
      }

      await cacheState.clearProgress(for: episode.id)
      try await repo.updateDownloadTaskID(episode.id, nil)
      Self.log.notice("Episode \(episode.toString) completed with error")
    } catch {
      Self.log.error(error)
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    guard let id = session.configuration.identifier else { return }
    complete(for: URLSessionConfiguration.ID(id))
  }
}
