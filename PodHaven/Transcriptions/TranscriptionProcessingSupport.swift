// Copyright Justin Bishop, 2026

import Foundation

enum QueueRemovalOperation: String, Sendable {
  case missingEpisode
  case alreadyTranscribed
  case completedTranscription
  case publisherTranscript
}

struct QueueMutationFailure: Error, LocalizedError {
  let operation: QueueRemovalOperation
  let message: String

  var errorDescription: String? {
    "\(operation.rawValue): \(message)"
  }
}

struct TranscriptionWorkModeChanged: Error {}

extension PublisherTranscriptImporter {
  func importAndStoreIfAbsent(
    for episode: Episode,
    in repo: any Databasing
  ) async throws -> Bool {
    guard
      let imported = try await importTranscript(
        from: episode.publisherTranscriptReferences
      )
    else {
      return false
    }
    return try await repo.storeTranscriptIfAbsent(
      episode.id,
      transcript: imported.transcript,
      publisherSource: imported.source
    )
  }
}
