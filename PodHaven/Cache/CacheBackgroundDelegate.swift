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
  private var sharedState: SharedState { Container.shared.sharedState() }
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
        sharedState.updateDownloadProgress(
          for: episode.id,
          progress: Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        )
      }
    } catch {
      Self.log.caughtError(
        "didWriteData: failed to update download progress for task #\(downloadTask.taskID)",
        error
      )
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
      Self.log.caughtError(
        "didFinishDownloadingTo: failed to move \(location) to safe temp \(safeTempURL)",
        error
      )
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
    let episode: Episode
    do {
      guard let fetched = try await repo.episode(downloadTask.taskID) else {
        Self.log.debug("No episode for task #\(downloadTask.taskID)?")
        do {
          try fileManager.removeItem(at: location)
        } catch {
          Self.log.caughtError(
            "didFinishDownloadingTo: failed to remove orphaned temp file at \(location) for task #\(downloadTask.taskID)",
            error
          )
        }
        return
      }
      episode = fetched
    } catch {
      Self.log.caughtError(
        "didFinishDownloadingTo: failed to fetch episode for task #\(downloadTask.taskID)",
        error
      )
      return
    }

    do {
      try await repo.updateDownloadTaskID(episode.id, downloadTaskID: nil)
    } catch {
      Self.log.caughtError(
        "didFinishDownloadingTo: failed to clear download task ID for \(episode.toString)",
        error
      )
    }
    sharedState.clearDownloadProgress(for: episode.id)

    let fileName = generateCacheFilename(for: episode)
    let destURL = CacheManager.resolveCachedFilepath(for: fileName)
    if fileManager.fileExists(at: destURL.rawValue) {
      Self.log.notice("File already cached for \(episode.id) at \(destURL), removing")
      do {
        try fileManager.removeItem(at: destURL.rawValue)
      } catch {
        Self.log.caughtError(
          "didFinishDownloadingTo: failed to remove existing cached file at \(destURL) for \(episode.toString)",
          error
        )
        return
      }
    }

    do {
      try fileManager.moveItem(at: location, to: destURL.rawValue)
    } catch {
      Self.log.caughtError(
        "didFinishDownloadingTo: failed to move downloaded file to \(destURL) for \(episode.toString)",
        error
      )
      return
    }

    let episodeAsset: EpisodeAsset
    do {
      episodeAsset = try await loadEpisodeAsset(AVURLAsset(url: destURL.rawValue))
    } catch {
      Self.log.caughtError(
        "didFinishDownloadingTo: failed to load asset at \(destURL) for \(episode.toString)",
        error
      )
      do {
        try fileManager.removeItem(at: destURL.rawValue)
      } catch {
        Self.log.caughtError(
          "didFinishDownloadingTo: failed to clean up file at \(destURL) after asset load failure",
          error
        )
      }
      return
    }

    guard episodeAsset.isPlayable else {
      Self.log.error(
        """
        MediaGUID Not Playable
          Episode: \(episode.toString)
          MediaGUID: \(episode.unsaved.id)
        """
      )
      do {
        try fileManager.removeItem(at: destURL.rawValue)
      } catch {
        Self.log.caughtError(
          "didFinishDownloadingTo: failed to remove unplayable file at \(destURL)",
          error
        )
      }
      return
    }

    do {
      try await repo.updateDuration(episode.id, duration: episodeAsset.duration)
    } catch {
      Self.log.caughtError(
        "didFinishDownloadingTo: failed to update duration for \(episode.toString)",
        error
      )
      return
    }

    do {
      try await repo.updateCachedFilename(episode.id, cachedFilename: fileName)
    } catch {
      Self.log.caughtError(
        "didFinishDownloadingTo: failed to update cached filename for \(episode.toString) to \(fileName)",
        error
      )
      return
    }

    Self.log.debug("Cached episode \(episode.id) to \(fileName)")
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
    guard let downloadError = error else { return }

    let episode: Episode?
    do {
      episode = try await repo.episode(task.taskID)
    } catch {
      Self.log.caughtError(
        "didCompleteWithError: failed to fetch episode for task #\(task.taskID)",
        error
      )
      Self.log.caughtError("Download failed for task #\(task.taskID)", downloadError)
      return
    }

    guard let episode else {
      Self.log.warning("No episode for task #\(task.taskID)?")
      Self.log.caughtError("Download failed for unknown task #\(task.taskID)", downloadError)
      return
    }

    sharedState.clearDownloadProgress(for: episode.id)

    do {
      try await repo.updateDownloadTaskID(episode.id, downloadTaskID: nil)
    } catch {
      Self.log.caughtError(
        "didCompleteWithError: failed to clear download task ID for \(episode.toString)",
        error
      )
    }

    Self.log.caughtError("Episode \(episode.toString) download failed", downloadError)
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
