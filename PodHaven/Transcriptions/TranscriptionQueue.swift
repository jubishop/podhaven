// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging

// MARK: - Container

extension Container {
  var transcriptionQueue: Factory<TranscriptionQueue> {
    Factory(self) { TranscriptionQueue() }.scope(.cached)
  }
}

// MARK: - TranscriptionStatus

enum TranscriptionStatus: Hashable, Sendable {
  case none
  case queued
  case transcribing(Double)
  case transcribed
  case failed

  var canTranscribe: Bool {
    switch self {
    case .none, .failed: return true
    case .queued, .transcribing, .transcribed: return false
    }
  }
}

// MARK: - TranscriptionQueue

struct TranscriptionQueue: Sendable {
  private static let log = Log.as(LogSubsystem.Transcription.queue)

  // Persisted ordered work-list in UserDefaults (not SQLite): survives
  // termination so TranscriptionProcessor can resume the head on next launch.
  @PersistedBroadcast("transcriptionQueue") var episodeIDs: [Episode.ID] = []

  // The in-flight episode's progress (0...1). At most one entry, mirroring
  // SharedState.downloadProgress.
  @Broadcasted var progress: [Episode.ID: Double] = [:]

  // Episodes whose last attempt failed, surfaced until retried or dismissed.
  @Broadcasted var failed: Set<Episode.ID> = []

  fileprivate init() {}

  // MARK: - Mutations

  func enqueue(_ episodeID: Episode.ID) {
    $failed.update { _ = $0.remove(episodeID) }
    $episodeIDs.update { ids in
      guard !ids.contains(episodeID) else { return }
      ids.append(episodeID)
    }
    Self.log.debug("enqueued \(episodeID); depth \(episodeIDs.count)")
  }

  func enqueue(_ ids: [Episode.ID]) {
    for id in ids { enqueue(id) }
  }

  func remove(_ episodeID: Episode.ID) {
    $episodeIDs.update { $0.removeAll { $0 == episodeID } }
    $progress.update { _ = $0.removeValue(forKey: episodeID) }
  }

  // MARK: - Progress

  func setProgress(_ value: Double, for episodeID: Episode.ID) {
    Assert.precondition(
      value >= 0 && value <= 1,
      "progress must be between 0 and 1 but is \(value)"
    )
    $progress.update { $0[episodeID] = value }
  }

  func clearProgress(for episodeID: Episode.ID) {
    $progress.update { _ = $0.removeValue(forKey: episodeID) }
  }

  // MARK: - Failure

  func fail(_ episodeID: Episode.ID) {
    $episodeIDs.update { $0.removeAll { $0 == episodeID } }
    $progress.update { _ = $0.removeValue(forKey: episodeID) }
    $failed.update { _ = $0.insert(episodeID) }
  }

  func clearFailed(_ episodeID: Episode.ID) {
    $failed.update { _ = $0.remove(episodeID) }
  }

  // MARK: - Status

  func status(for episodeID: Episode.ID, hasTranscript: Bool) -> TranscriptionStatus {
    if hasTranscript { return .transcribed }
    if let value = progress[episodeID] { return .transcribing(value) }
    if episodeIDs.contains(episodeID) { return .queued }
    if failed.contains(episodeID) { return .failed }
    return .none
  }
}
