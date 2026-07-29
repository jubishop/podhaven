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
  private struct FinalizationState: Sendable {
    var inFlightCount = 0
    var completionRequested = false
  }

  private var cacheManager: CacheManager { Container.shared.cacheManager() }
  private var cacheFileStore: CacheFileStore { Container.shared.cacheFileStore() }
  private var repo: any Databasing { Container.shared.repo() }
  private var sharedState: SharedState { Container.shared.sharedState() }
  private var sleeper: any Sleepable { Container.shared.sleeper() }
  private var fileManager: any FileManaging { Container.shared.fileManager() }
  private var loadEpisodeAsset: (_ asset: AVURLAsset) async throws -> EpisodeAsset {
    Container.shared.loadEpisodeAsset()
  }

  private static let log = Log.as(LogSubsystem.Cache.backgroundDelegate)

  private let completions = ThreadSafe<[URLSessionConfiguration.ID: @MainActor () -> Void]>([:])
  private let finalizations = ThreadSafe<[URLSessionConfiguration.ID: FinalizationState]>([:])

  // MARK: - Completion Management

  func store(id: URLSessionConfiguration.ID, completion: @escaping @MainActor () -> Void) {
    completions[id] = completion
  }

  func complete(for id: URLSessionConfiguration.ID) {
    let shouldComplete = finalizations { states in
      guard var state = states[id] else { return true }
      state.completionRequested = true
      states[id] = state
      return false
    }
    guard shouldComplete else { return }
    invokeCompletion(for: id)
  }

  private func invokeCompletion(for id: URLSessionConfiguration.ID) {
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
      if let episode = try await self.episode(for: downloadTask) {
        sharedState.updateDownloadProgress(
          for: episode.id,
          progress: Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        )
      }
    } catch {
      Self.log.caughtError(
        """
        didWriteData: failed to update download progress for task #\(downloadTask.taskID) \
        (description: \(downloadTask.taskDescription ?? "nil"))
        """,
        error
      )
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    var safeTempURL = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    safeTempURL.appendPathExtension(
      cacheFileExtension(for: downloadTask.originalRequest?.url)
    )
    do {
      try fileManager.moveItem(at: location, to: safeTempURL)
    } catch {
      Self.log.caughtError(
        "didFinishDownloadingTo: failed to move \(location) to safe temp \(safeTempURL)",
        error
      )
      // The async path that clears state and signals completion won't run here,
      // so do it inline to avoid stranding the episode as downloading.
      guard let signalAttempt = downloadAttempt(for: downloadTask) else { return }
      let finalizationSessionID = beginFinalization(for: sessionID(for: session))
      Task { [weak self] in
        guard let self else { return }
        await self.performProtectedFinalization(for: finalizationSessionID) {
          await self.clearDownloadState(for: signalAttempt.episodeID)
          self.cacheManager.signalDownloadComplete(for: signalAttempt)
        }
      }
      return
    }

    let finalizationSessionID = beginFinalization(for: sessionID(for: session))
    Task { [weak self] in
      guard let self else { return }
      await self.performProtectedFinalization(for: finalizationSessionID) {
        await self.processDownloadedFile(downloadTask: downloadTask, location: safeTempURL)
      }
    }
  }
  func urlSession(
    _ session: any DataFetchable,
    downloadTask: any DownloadingTask,
    didFinishDownloadingTo location: URL
  ) async {
    let finalizationSessionID = beginFinalization(for: sessionID(for: session))
    await performProtectedFinalization(for: finalizationSessionID) { [weak self] in
      guard let self else { return }
      await self.processDownloadedFile(downloadTask: downloadTask, location: location)
    }
  }

  private func processDownloadedFile(
    downloadTask: any DownloadingTask,
    location: URL
  ) async {
    // Signal on every exit so an awaiter resumes, even if the row was deleted.
    let signalAttempt = downloadAttempt(for: downloadTask)
    let signalEpisodeID = signalAttempt?.episodeID
    defer {
      if let signalAttempt { cacheManager.signalDownloadComplete(for: signalAttempt) }
    }

    let episode: Episode
    do {
      guard let fetched = try await self.episode(for: downloadTask) else {
        Self.log.debug(
          """
          No episode for task #\(downloadTask.taskID) \
          (description: \(downloadTask.taskDescription ?? "nil"))
          """
        )
        do {
          try fileManager.removeItem(at: location)
        } catch {
          Self.log.caughtError(
            """
            didFinishDownloadingTo: failed to remove orphaned temp file \
            at \(location) for task #\(downloadTask.taskID)
            """,
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
      // The row may still exist with downloading == true; clear it via the
      // parsed id and drop the temp file we can't attribute.
      if let signalEpisodeID { await clearDownloadState(for: signalEpisodeID) }
      do {
        try fileManager.removeItem(at: location)
      } catch {
        Self.log.caughtError(
          "didFinishDownloadingTo: failed to remove temp file at \(location) after fetch failure",
          error
        )
      }
      return
    }

    // Defensive guard: even with taskDescription routing the lookup, refuse
    // to attribute a downloaded file to an episode whose mediaURL doesn't
    // match what was actually fetched. Catches future regressions in the
    // attribution pipeline.
    if let requestedURL = downloadTask.originalRequest?.url,
      requestedURL != episode.mediaURL.rawValue
    {
      Self.log.error(
        """
        didFinishDownloadingTo: URL mismatch for task #\(downloadTask.taskID) \
        — refusing to attribute download
          episode: \(episode.toString)
          episode.mediaURL: \(episode.mediaURL.rawValue)
          task.originalRequest.url: \(requestedURL)
        """
      )
      do {
        try fileManager.removeItem(at: location)
      } catch {
        Self.log.caughtError(
          "didFinishDownloadingTo: failed to remove misattributed file at \(location)",
          error
        )
      }
      await clearDownloadState(for: episode.id)
      return
    }

    sharedState.clearDownloadProgress(for: episode.id)

    let fileName = generateCacheFilename(for: episode)
    let destURL = CacheManager.resolveCachedFilepath(for: fileName)

    let episodeAsset: EpisodeAsset
    do {
      episodeAsset = try await loadEpisodeAsset(AVURLAsset(url: location))
    } catch {
      Self.log.caughtError(
        "didFinishDownloadingTo: failed to load downloaded asset for \(episode.toString)",
        error
      )
      do {
        try fileManager.removeItem(at: location)
      } catch {
        Self.log.caughtError(
          "didFinishDownloadingTo: failed to clean up \(location) after asset load failure",
          error
        )
      }
      await clearDownloadState(for: episode.id)
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
        try fileManager.removeItem(at: location)
      } catch {
        Self.log.caughtError(
          "didFinishDownloadingTo: failed to remove unplayable file at \(location)",
          error
        )
      }
      await clearDownloadState(for: episode.id)
      return
    }

    let storage: CacheFileStorage?
    do {
      storage = try await cacheFileStore.storeDownloadedFile(
        at: location,
        for: episode.id,
        cachedFilename: fileName,
        duration: episodeAsset.duration
      )
    } catch {
      Self.log.caughtError(
        "didFinishDownloadingTo: failed to store downloaded file at \(destURL) for \(episode.toString)",
        error
      )
      if fileManager.fileExists(at: location) {
        do {
          try fileManager.removeItem(at: location)
        } catch {
          Self.log.caughtError(
            "didFinishDownloadingTo: failed to clean up \(location) after storage failure",
            error
          )
        }
      }
      await clearDownloadState(for: episode.id)
      return
    }

    guard let storage else {
      Self.log.debug(
        "didFinishDownloadingTo: cache state changed before storing \(episode.toString)"
      )
      do {
        try fileManager.removeItem(at: location)
      } catch {
        Self.log.caughtError(
          "didFinishDownloadingTo: failed to remove superseded file at \(location)",
          error
        )
      }
      return
    }

    if case .reused = storage {
      do {
        try fileManager.removeItem(at: location)
      } catch {
        Self.log.caughtError(
          "didFinishDownloadingTo: failed to remove duplicate file at \(location)",
          error
        )
      }
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

    guard error != nil else { return }
    let finalizationSessionID = beginFinalization(for: sessionID(for: session))
    Task { [weak self] in
      guard let self else { return }
      await self.performProtectedFinalization(for: finalizationSessionID) {
        await self.urlSession(session, task: downloadTask, didCompleteWithError: error)
      }
    }
  }
  func urlSession(
    _ session: any DataFetchable,
    task: any DownloadingTask,
    didCompleteWithError error: (any Error)?
  ) async {
    guard let downloadError = error else { return }

    // A failure unblocks any awaiter; success is signaled by didFinishDownloadingTo.
    let signalAttempt = downloadAttempt(for: task)
    let signalEpisodeID = signalAttempt?.episodeID
    defer {
      if let signalAttempt { cacheManager.signalDownloadComplete(for: signalAttempt) }
    }

    let episode: Episode?
    do {
      episode = try await self.episode(for: task)
    } catch {
      Self.log.caughtError(
        "didCompleteWithError: failed to fetch episode for task #\(task.taskID)",
        error
      )
      Self.log.caughtError("Download failed for task #\(task.taskID)", downloadError)
      // The row may still exist with downloading == true; clear it via the
      // parsed id so the episode isn't stranded as .caching.
      if let signalEpisodeID { await clearDownloadState(for: signalEpisodeID) }
      return
    }

    guard let episode else {
      Self.log.warning(
        """
        No episode for task #\(task.taskID) \
        (description: \(task.taskDescription ?? "nil"))
        """
      )
      Self.log.caughtError("Download failed for unknown task #\(task.taskID)", downloadError)
      return
    }

    await clearDownloadState(for: episode.id)

    Self.log.caughtError("Episode \(episode.toString) download failed", downloadError)
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    guard let id = session.configuration.identifier else { return }
    complete(for: URLSessionConfiguration.ID(id))
  }

  // MARK: - Private Helpers

  private func beginFinalization(for id: URLSessionConfiguration.ID?)
    -> URLSessionConfiguration.ID?
  {
    guard let id else { return nil }
    finalizations { states in
      var state = states[id, default: FinalizationState()]
      state.inFlightCount += 1
      states[id] = state
    }
    return id
  }

  private func performProtectedFinalization(
    for id: URLSessionConfiguration.ID?,
    operation: () async -> Void
  ) async {
    let backgroundTask = await BackgroundTask.start(withName: "cacheDownloadFinalization")
    await operation()
    await backgroundTask.end()
    finishFinalization(for: id)
  }

  private func finishFinalization(for id: URLSessionConfiguration.ID?) {
    guard let id else { return }
    let shouldComplete = finalizations { states -> Bool in
      guard var state = states[id] else {
        Assert.fatal("Missing finalization state for background session \(id)")
      }
      Assert.precondition(
        state.inFlightCount > 0,
        "Invalid finalization count for background session \(id)"
      )
      state.inFlightCount -= 1
      guard state.inFlightCount == 0 else {
        states[id] = state
        return false
      }
      states.removeValue(forKey: id)
      return state.completionRequested
    }
    if shouldComplete { invokeCompletion(for: id) }
  }

  private func sessionID(for session: any DataFetchable) -> URLSessionConfiguration.ID? {
    guard let session = session as? URLSession,
      let identifier = session.configuration.identifier
    else { return nil }
    return URLSessionConfiguration.ID(identifier)
  }

  // Resolve a finished/failed download back to its episode using the
  // taskDescription set when the task was created. URLSession taskIDs are
  // session-scoped and reset on each background-session creation, so they
  // can't be trusted to map a task to a row that survived an app relaunch.
  private func episode(for task: any DownloadingTask) async throws -> Episode? {
    guard let episodeID = episodeID(for: task) else { return nil }
    return try await repo.episode(episodeID)
  }

  // Parse the episode id from taskDescription without a DB hit, so completion
  // can be signaled even if the row was deleted mid-download.
  private func episodeID(for task: any DownloadingTask) -> Episode.ID? {
    guard let description = task.taskDescription,
      let raw = Episode.ID.RawValue(description)
    else { return nil }
    return Episode.ID(rawValue: raw)
  }

  private func downloadAttempt(for task: any DownloadingTask) -> CacheDownloadAttempt? {
    guard let episodeID = episodeID(for: task) else { return nil }
    return CacheDownloadAttempt(episodeID: episodeID, taskID: task.taskID)
  }

  // Clears progress + downloading flag; logs rather than propagates a failure.
  private func clearDownloadState(for episodeID: Episode.ID) async {
    sharedState.clearDownloadProgress(for: episodeID)
    do {
      try await repo.updateDownloading(episodeID, downloading: false)
    } catch {
      Self.log.caughtError("failed to clear downloading flag for \(episodeID)", error)
    }
  }

  private func generateCacheFilename(for episode: Episode) -> String {
    let mediaURL = episode.mediaURL.rawValue
    let fileExtension = cacheFileExtension(for: mediaURL)
    return "\(mediaURL.hash(to: 12)).\(fileExtension)"
  }

  private func cacheFileExtension(for mediaURL: URL?) -> String {
    guard let fileExtension = mediaURL?.pathExtension, !fileExtension.isEmpty else { return "mp3" }
    return fileExtension
  }
}
