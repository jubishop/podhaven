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
  private var taskMap: TaskMapStore { Container.shared.cacheTaskMapStore() }

  private static let log = Log.as("CacheBackgroundDelegate")

  // These internal helpers are used by the delegate to reuse logic.
  func handleDidFinish(taskIdentifier: Int, location: URL) async {
    defer { Task { await taskMap.remove(taskID: taskIdentifier) } }

    guard let mg = await taskMap.key(for: taskIdentifier) else {
      Self.log.warning("handleDidFinish: No mapping for task \(taskIdentifier)")
      return
    }

    do {
      guard let episode = try await repo.episode(mg) else {
        Self.log.warning("Episode not found for guid: \(mg)")
        return
      }

      if episode.queued == false {
        Self.log.debug("Episode dequeued mid-download; skipping cache move for \(episode.id)")
        try? FileManager.default.removeItem(at: location)
        await (await cacheState).markFinished(episode.id)
        return
      }

      let fileName = CacheManager.generateCacheFilenameStatic(for: episode)
      let destURL = CacheManager.resolveCachedFilepath(for: fileName)
      try? FileManager.default.removeItem(at: destURL)
      try FileManager.default.moveItem(at: location, to: destURL)
      _ = try await repo.updateCachedFilename(episode.id, fileName)

      await (await cacheState).markFinished(episode.id)
      Self.log.debug("Cached episode \(episode.id) to \(fileName)")
    } catch {
      Self.log.error(error)
    }
  }

  func handleDidComplete(taskIdentifier: Int, error: Error) async {
    if let mg = await taskMap.key(for: taskIdentifier) {
      do {
        if let episode = try await repo.episode(mg) {
          await (await cacheState).markFailed(episode.id, error: error)
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
      if let mg = await taskMap.key(for: downloadTask.taskIdentifier) {
        await (await cacheState).updateProgress(for: mg, progress: progress)
      }
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    Task {
      await handleDidFinish(taskIdentifier: downloadTask.taskIdentifier, location: location)
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let error else { return }
    Task { await handleDidComplete(taskIdentifier: task.taskIdentifier, error: error) }
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

  var cacheBackgroundSession: Factory<URLSession> {
    Factory(self) {
      let identifier = (Bundle.main.bundleIdentifier ?? "PodHaven") + ".cache.bg"
      let config = URLSessionConfiguration.background(withIdentifier: identifier)
      config.sessionSendsLaunchEvents = true
      config.allowsCellularAccess = true
      config.waitsForConnectivity = true
      config.isDiscretionary = false
      config.httpMaximumConnectionsPerHost = 4
      return URLSession(
        configuration: config,
        delegate: self.cacheBackgroundDelegate(),
        delegateQueue: nil
      )
    }
    .scope(.cached)
  }
}
