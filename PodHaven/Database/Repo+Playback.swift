// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import GRDB
import Logging

extension Repo {
  private static var playbackLog: Logger {
    Log.as(LogSubsystem.Database.repo)
  }

  @discardableResult
  func updateCurrentTime(_ episodeID: Episode.ID, currentTime: CMTime) async throws -> Bool {
    Self.playbackLog.trace("updateCurrentTime: \(episodeID) to \(currentTime)")

    let updated = try await writer.write(level: .trace) { db in
      let wasStarted = try Bool.fetchOne(
        db,
        Episode
          .withID(episodeID)
          .select(Episode.Columns.playbackStarted, as: Bool.self)
      )
      guard let wasStarted else { return false }

      var assignments: [ColumnAssignment] = [
        Episode.Columns.currentTime.set(to: currentTime),
        Episode.Columns.maxPlaybackTime.set(
          to: sqlMax(Episode.Columns.maxPlaybackTime, currentTime)
        ),
      ]
      // playbackStarted is assigned only when playback crosses zero; steady
      // writes must not put the column in the commit's changed set.
      let isStarted = currentTime.seconds > 0
      if isStarted != wasStarted {
        assignments.append(Episode.Columns.playbackStarted.set(to: isStarted))
      }

      return
        try Episode
        .withID(episodeID)
        .updateAll(db, assignments) > 0
    }
    if updated { writer.notifySettledPlaybackPosition() }
    return updated
  }

  // Caller passes the previous-checkpoint position as `playedFrom` so the
  // bitmap OR-marks exactly the seconds elapsed since last save. Backward
  // and zero-progress ranges leave the bitmap untouched.
  @discardableResult
  func updatePlayback(
    _ episodeID: Episode.ID,
    currentTime: CMTime,
    playedFrom: CMTime,
    now: Date
  ) async throws -> Bool {
    Self.playbackLog.trace(
      "updatePlayback: \(episodeID) to \(currentTime) (from \(playedFrom))"
    )

    return try await writer.write(level: .trace) { db in
      let row = try Row.fetchOne(
        db,
        Episode
          .withID(episodeID)
          .select(
            Episode.Columns.duration,
            Episode.Columns.playbackCoverage,
            Episode.Columns.playbackStarted
          )
      )
      guard let row else { return false }

      var assignments: [ColumnAssignment] = [
        Episode.Columns.currentTime.set(to: currentTime),
        Episode.Columns.maxPlaybackTime.set(
          to: sqlMax(Episode.Columns.maxPlaybackTime, currentTime)
        ),
        Episode.Columns.lastPlayedDate.set(to: now),
      ]

      // playbackStarted is assigned only when playback crosses zero; steady
      // checkpoint writes must not put the column in the commit's changed set.
      let wasStarted: Bool = row[Episode.Columns.playbackStarted]
      let isStarted = currentTime.seconds > 0
      if isStarted != wasStarted {
        assignments.append(Episode.Columns.playbackStarted.set(to: isStarted))
      }

      let duration: CMTime? = row[Episode.Columns.duration]
      let durationSeconds = duration?.positiveFiniteSeconds ?? 0
      let startSeconds = playedFrom.positiveFiniteSeconds
      let endSeconds = currentTime.positiveFiniteSeconds

      if durationSeconds > 0, endSeconds > startSeconds {
        let existing: Data? = row[Episode.Columns.playbackCoverage]
        var coverage = PlaybackCoverage(durationSeconds: durationSeconds, data: existing)
        if coverage.mark(startSeconds: startSeconds, endSeconds: endSeconds) {
          assignments.append(Episode.Columns.playbackCoverage.set(to: coverage.data))
        }
      }

      return
        try Episode
        .withID(episodeID)
        .updateAll(db, assignments) > 0
    }
  }

  @discardableResult
  func markFinished(_ episodeIDs: [Episode.ID], finishDate: FinishDateUpdate) async throws -> Int {
    Self.playbackLog.debug("markFinished: \(episodeIDs), finishDate: \(finishDate)")

    guard !episodeIDs.isEmpty else { return 0 }

    let now = Container.shared.dateProvider().now
    return try await writer.write { db in
      let finishDateAssignment =
        switch finishDate {
        case .keepExisting: Episode.Columns.finishDate.set(to: Episode.Columns.finishDate ?? now)
        case .now: Episode.Columns.finishDate.set(to: now)
        }
      return
        try Episode
        .withIDs(episodeIDs)
        .updateAll(
          db,
          finishDateAssignment,
          Episode.Columns.currentTime.set(to: 0),
          Episode.Columns.maxPlaybackTime.set(to: 0),
          Episode.Columns.playbackStarted.set(to: false)
        )
    }
  }

  @discardableResult
  func markFinished(_ episodeID: Episode.ID, finishDate: FinishDateUpdate) async throws -> Bool {
    try await markFinished([episodeID], finishDate: finishDate) > 0
  }
}
