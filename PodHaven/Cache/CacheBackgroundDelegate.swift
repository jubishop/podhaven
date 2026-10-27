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

  private enum InvalidatedDownloadLocation {
    case cacheDestination(CachedURL)
    case temporary(URL)
  }

  private enum DownloadAttemptOwnership {
    case unattributed
    case claimed(CacheDownloadAttempt)
    case inactive(CacheDownloadAttempt)

    var attempt: CacheDownloadAttempt? {
      switch self {
      case .unattributed:
        nil
      case .claimed(let attempt), .inactive(let attempt):
        attempt
      }
    }
  }

  private var cacheManager: CacheManager { Container.shared.cacheManager() }
  private var cacheFileStore: CacheFileStore { Container.shared.cacheFileStore() }
  private var repo: any Databasing { Container.shared.repo() }
  private var sleeper: any Sleepable { Container.shared.sleeper() }
  private var fileManager: any FileManaging { Container.shared.fileManager() }
  private var loadEpisodeAsset: @concurrent (_ url: URL) async throws -> EpisodeAsset {
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
        cacheManager.updateDownloadProgress(
          Double(totalBytesWritten) / Double(totalBytesExpectedToWrite),
          for: CacheDownloadAttempt(episodeID: episode.id, taskID: downloadTask.taskID)
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
    let ownership = claimDownloadCompletion(for: downloadTask)
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
      switch ownership {
      case .claimed(let attempt):
        let finalizationSessionID = beginFinalization(for: sessionID(for: session))
        Task { [weak self] in
          guard let self else { return }
          await self.performProtectedFinalization(for: finalizationSessionID) {
            defer { self.cacheManager.signalDownloadComplete(for: attempt) }
            guard self.cacheManager.isDownloadActive(attempt) else { return }
            await self.clearDownloadState(for: attempt)
          }
        }
      case .inactive(let attempt):
        cacheManager.signalDownloadComplete(for: attempt)
      case .unattributed:
        break
      }
      return
    }

    let finalizationSessionID = beginFinalization(for: sessionID(for: session))
    Task { [weak self] in
      guard let self else { return }
      await self.performProtectedFinalization(for: finalizationSessionID) {
        await self.processDownloadedFile(
          downloadTask: downloadTask,
          location: safeTempURL,
          ownership: ownership
        )
      }
    }
  }
  func urlSession(
    _ session: any DataFetchable,
    downloadTask: any DownloadingTask,
    didFinishDownloadingTo location: URL
  ) async {
    let ownership = claimDownloadCompletion(for: downloadTask)
    let finalizationSessionID = beginFinalization(for: sessionID(for: session))
    await performProtectedFinalization(for: finalizationSessionID) { [weak self] in
      guard let self else { return }
      await self.processDownloadedFile(
        downloadTask: downloadTask,
        location: location,
        ownership: ownership
      )
    }
  }

  private func processDownloadedFile(
    downloadTask: any DownloadingTask,
    location: URL,
    ownership: DownloadAttemptOwnership
  ) async {
    // Signal on every exit so an awaiter resumes, even if the row was deleted.
    let signalAttempt = ownership.attempt
    defer {
      if let signalAttempt { cacheManager.signalDownloadComplete(for: signalAttempt) }
    }
    if case .inactive(let attempt) = ownership {
      await cleanUpInvalidatedDownload(at: .temporary(location), attempt: attempt)
      return
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
      if let signalAttempt, !cacheManager.isDownloadActive(signalAttempt) {
        await cleanUpInvalidatedDownload(at: .temporary(location), attempt: signalAttempt)
        return
      }
      // The row may still exist with downloading == true; clear it via the
      // parsed attempt and drop the temp file we can't attribute.
      if let signalAttempt { await clearDownloadState(for: signalAttempt) }
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
    if let signalAttempt, !cacheManager.isDownloadActive(signalAttempt) {
      await cleanUpInvalidatedDownload(at: .temporary(location), attempt: signalAttempt)
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
      if let signalAttempt { await clearDownloadState(for: signalAttempt) }
      return
    }

    let fileName = generateCacheFilename(for: episode)
    let destURL = CacheManager.resolveCachedFilepath(for: fileName)

    let episodeAsset: EpisodeAsset
    do {
      episodeAsset = try await loadEpisodeAsset(location)
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
      if let signalAttempt { await clearDownloadState(for: signalAttempt) }
      return
    }
    if let signalAttempt, !cacheManager.isDownloadActive(signalAttempt) {
      await cleanUpInvalidatedDownload(at: .temporary(location), attempt: signalAttempt)
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
      if let signalAttempt { await clearDownloadState(for: signalAttempt) }
      return
    }

    let storage: CacheFileStorage?
    do {
      storage = try await cacheManager.storeDownloadedFileIfCurrent(
        at: location,
        for: CacheDownloadAttempt(episodeID: episode.id, taskID: downloadTask.taskID),
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
      if let signalAttempt { await clearDownloadState(for: signalAttempt) }
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

    if let signalAttempt, !cacheManager.isDownloadActive(signalAttempt) {
      switch storage {
      case .installed(let cachedURL):
        await cleanUpInvalidatedDownload(
          at: .cacheDestination(cachedURL),
          attempt: signalAttempt
        )
      case .reused:
        await cleanUpInvalidatedDownload(at: .temporary(location), attempt: signalAttempt)
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

    guard let downloadError = error else { return }
    let ownership = claimDownloadCompletion(for: downloadTask)
    let finalizationSessionID = beginFinalization(for: sessionID(for: session))
    Task { [weak self] in
      guard let self else { return }
      await self.performProtectedFinalization(for: finalizationSessionID) {
        await self.processDownloadFailure(
          task: downloadTask,
          downloadError: downloadError,
          ownership: ownership
        )
      }
    }
  }
  func urlSession(
    _ session: any DataFetchable,
    task: any DownloadingTask,
    didCompleteWithError error: (any Error)?
  ) async {
    guard let downloadError = error else { return }
    let ownership = claimDownloadCompletion(for: task)
    await processDownloadFailure(
      task: task,
      downloadError: downloadError,
      ownership: ownership
    )
  }

  private func processDownloadFailure(
    task: any DownloadingTask,
    downloadError: any Error,
    ownership: DownloadAttemptOwnership
  ) async {
    // A failure unblocks any awaiter; success is signaled by didFinishDownloadingTo.
    let signalAttempt = ownership.attempt
    defer {
      if let signalAttempt { cacheManager.signalDownloadComplete(for: signalAttempt) }
    }
    if case .inactive(let attempt) = ownership {
      logInactiveDownloadFailure(for: task, attempt: attempt, error: downloadError)
      return
    }

    let episode: Episode?
    do {
      episode = try await self.episode(for: task)
    } catch {
      if let signalAttempt, !cacheManager.isDownloadActive(signalAttempt) {
        logInactiveDownloadFailure(
          for: task,
          attempt: signalAttempt,
          error: downloadError
        )
        return
      }
      Self.log.caughtError(
        "didCompleteWithError: failed to fetch episode for task #\(task.taskID)",
        error
      )
      Self.log.caughtError("Download failed for task #\(task.taskID)", downloadError)
      // The row may still exist with downloading == true; clear it via the
      // parsed attempt so the episode isn't stranded as .caching.
      if let signalAttempt { await clearDownloadState(for: signalAttempt) }
      return
    }
    if let signalAttempt, !cacheManager.isDownloadActive(signalAttempt) {
      logInactiveDownloadFailure(
        for: task,
        attempt: signalAttempt,
        error: downloadError
      )
      return
    }

    guard let episode else {
      if let signalAttempt, cacheManager.isDownloadInvalidated(signalAttempt) {
        Self.log.caughtError(
          """
          No episode for task #\(task.taskID) because its download was invalidated \
          (description: \(task.taskDescription ?? "nil"))
          """,
          downloadError,
          level: .debug
        )
        return
      }
      Self.log.caughtError(
        """
        No episode for task #\(task.taskID) \
        (description: \(task.taskDescription ?? "nil"))
        """,
        downloadError,
        level: .warning
      )
      return
    }

    if let signalAttempt { await clearDownloadState(for: signalAttempt) }

    Self.log.caughtError("Episode \(episode.toString) download failed", downloadError)
  }

  private func logInactiveDownloadFailure(
    for task: any DownloadingTask,
    attempt: CacheDownloadAttempt,
    error: any Error
  ) {
    if cacheManager.isDownloadInvalidated(attempt) {
      Self.log.caughtError(
        """
        No episode for task #\(task.taskID) because its download was invalidated \
        (description: \(task.taskDescription ?? "nil"))
        """,
        error,
        level: .debug
      )
      return
    }
    Self.log.caughtError(
      "Ignored failure for inactive download attempt #\(attempt.taskID)",
      error,
      level: .debug
    )
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

  private func claimDownloadCompletion(
    for task: any DownloadingTask
  ) -> DownloadAttemptOwnership {
    guard let attempt = downloadAttempt(for: task) else { return .unattributed }
    guard cacheManager.claimDownloadCompletion(for: attempt) else {
      return .inactive(attempt)
    }
    return .claimed(attempt)
  }

  private func cleanUpInvalidatedDownload(
    at location: InvalidatedDownloadLocation,
    attempt: CacheDownloadAttempt
  ) async {
    let url: URL
    switch location {
    case .cacheDestination(let cachedURL):
      url = cachedURL.rawValue
      do {
        switch try await cacheFileStore.removeFileIfUnreferenced(cachedURL) {
        case .retained:
          Self.log.debug(
            "Preserved invalidated download file at \(url) referenced by a surviving episode"
          )
        case .removed:
          Self.log.debug(
            "Removed invalidated download file at \(url) for episode \(attempt.episodeID)"
          )
        case .alreadyMissing:
          Self.log.debug(
            "Invalidated download file already missing at \(url) for episode \(attempt.episodeID)"
          )
        }
      } catch {
        Self.log.caughtError(
          "Failed to clean up invalidated download file at \(url)",
          error
        )
      }
      return
    case .temporary(let temporaryURL):
      url = temporaryURL
    }

    do {
      try fileManager.removeItem(at: url)
      Self.log.debug(
        "Removed invalidated download file at \(url) for episode \(attempt.episodeID)"
      )
    } catch {
      if ErrorKit.isMissingFile(error) {
        Self.log.caughtError(
          "Invalidated download file already missing at \(url) for episode \(attempt.episodeID)",
          error,
          level: .debug
        )
      } else {
        Self.log.caughtError(
          "Failed to remove invalidated download file at \(url) for episode \(attempt.episodeID)",
          error
        )
      }
    }
  }

  // Clears the downloading flag; logs rather than propagates a failure.
  private func clearDownloadState(for attempt: CacheDownloadAttempt) async {
    do {
      try await cacheManager.clearDownloadIfCurrent(attempt)
    } catch {
      Self.log.caughtError("failed to clear downloading flag for \(attempt.episodeID)", error)
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
