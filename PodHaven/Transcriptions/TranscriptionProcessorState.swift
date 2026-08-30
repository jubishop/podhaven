// Copyright Justin Bishop, 2026

import Foundation

struct ActiveTranscription: Sendable {
  enum Interruption: Sendable {
    case none
    case pause
    case discard
    case requeue
    case deletion(AsyncLatch<Void>)
    case mediaServicesReset
    case publisherTranscript
    case replacementRequest
    case thermalPressure

    var isNone: Bool {
      if case .none = self { return true }
      return false
    }
  }

  let token: UUID
  let episodeID: Episode.ID
  let workMode: TranscriptionWorkMode
  let task: Task<Void, any Error>
  var interruption = Interruption.none
}

enum MediaServicesState: Sendable {
  case available
  case lost(AsyncLatch<Void>)
}

enum ForegroundState: Sendable {
  case active
  case background
}
