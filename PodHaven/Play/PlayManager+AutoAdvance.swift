// Copyright Justin Bishop, 2026

import Foundation
import Logging

extension PlayManager {
  enum AutoAdvancePhase: CustomStringConvertible, Sendable {
    case markingFinished
    case resolvingReplacement
    case loading(Episode.ID)
    case awaitingPlayback(UUID)

    var description: String {
      switch self {
      case .markingFinished: "markingFinished"
      case .resolvingReplacement: "resolvingReplacement"
      case .loading(let episodeID): "loading(\(episodeID))"
      case .awaitingPlayback: "awaitingPlayback"
      }
    }
  }

  enum AutoAdvanceEnd: String {
    case noPlayback, playing, replaced, superseded
  }

  struct AutoAdvance {
    let backgroundTask: BackgroundTask
    let id: UUID
    let phase: ThreadSafe<AutoAdvancePhase>
    let startedAt: Date
  }

  // iOS keeps a background audio app running only while audio plays, so
  // automatic advancement holds background time until its replacement plays.
  func beginAutoAdvance() async -> UUID {
    let id = UUID()
    let phase = ThreadSafe(AutoAdvancePhase.markingFinished)
    let startedAt = Date()
    let backgroundTask = await BackgroundTask.start(withName: "autoAdvance") { [phase] in
      Self.log.warning(
        """
        event=autoAdvanceExpired phase=\(phase()) \
        elapsedSeconds=\(Date().timeIntervalSince(startedAt))
        """
      )
    }
    if let autoAdvance { endAutoAdvance(autoAdvance.id, reason: .replaced) }
    autoAdvance = AutoAdvance(
      backgroundTask: backgroundTask,
      id: id,
      phase: phase,
      startedAt: startedAt
    )
    return id
  }

  func setAutoAdvancePhase(_ id: UUID?, to phase: AutoAdvancePhase) {
    guard let autoAdvance, autoAdvance.id == id else { return }
    autoAdvance.phase(phase)
  }

  // Once the replacement's playback is requested, only observed playback or a
  // newer playback request ends the advancement.
  func settleAutoAdvanceTransition(_ id: UUID?) {
    guard let autoAdvance, autoAdvance.id == id else { return }
    if case .awaitingPlayback = autoAdvance.phase() { return }
    endAutoAdvance(id, reason: .noPlayback)
  }

  func settleAutoAdvancePlayback(_ status: PlaybackStatus) {
    guard status == .playing, let autoAdvance,
      case .awaitingPlayback = autoAdvance.phase()
    else { return }
    endAutoAdvance(autoAdvance.id, reason: .playing)
  }

  func supersedeAutoAdvance(by requestID: UUID) {
    guard let autoAdvance, case .awaitingPlayback(let ownerID) = autoAdvance.phase(),
      ownerID != requestID
    else { return }
    endAutoAdvance(autoAdvance.id, reason: .superseded)
  }

  private func endAutoAdvance(_ id: UUID?, reason: AutoAdvanceEnd) {
    guard let autoAdvance, autoAdvance.id == id else { return }
    self.autoAdvance = nil
    Self.log.debug(
      """
      event=autoAdvanceEnded reason=\(reason.rawValue) phase=\(autoAdvance.phase()) \
      elapsedSeconds=\(Date().timeIntervalSince(autoAdvance.startedAt))
      """
    )
    let backgroundTask = autoAdvance.backgroundTask
    Task { @MainActor in backgroundTask.end() }
  }
}
