// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of repo.updatePlayback tests", .container)
class PlaybackCoverageRepoTests {
  @DynamicInjected(\.repo) private var repo

  // MARK: - Helpers

  private func insertEpisode(durationSeconds: Int) async throws -> Episode {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(
      duration: CMTime.seconds(Double(durationSeconds))
    )
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [unsavedEpisode]
      )
    )
    return series.episodes.first!
  }

  private func loadCoverage(for episodeID: Episode.ID, durationSeconds: Int)
    async throws -> PlaybackCoverage?
  {
    try await repo.db.read { db in
      let row = try Row.fetchOne(
        db,
        Episode.withID(episodeID).select(Episode.Columns.playbackCoverage)
      )
      guard let row, let data: Data = row[Episode.Columns.playbackCoverage] else {
        return nil
      }
      return PlaybackCoverage(durationSeconds: durationSeconds, data: data)
    }
  }

  // MARK: - Tests

  @Test("updatePlayback writes currentTime, lastPlayedDate, and bitmap atomically")
  func writesAllFields() async throws {
    let episode = try await insertEpisode(durationSeconds: 60)
    let now = Date()

    try await repo.updatePlayback(
      episode.id,
      currentTime: CMTime.seconds(15),
      playedFrom: CMTime.seconds(0),
      now: now
    )

    let row = try await repo.db.read { db in
      try Row.fetchOne(
        db,
        Episode.withID(episode.id)
          .select(
            Episode.Columns.currentTime,
            Episode.Columns.maxPlaybackTime,
            Episode.Columns.lastPlayedDate,
            Episode.Columns.playbackCoverage
          )
      )
    }
    let unwrapped = try #require(row)
    let currentTime: CMTime = unwrapped[Episode.Columns.currentTime]
    let maxPlayback: CMTime = unwrapped[Episode.Columns.maxPlaybackTime]
    let lastPlayed: Date? = unwrapped[Episode.Columns.lastPlayedDate]
    let bitmap: Data? = unwrapped[Episode.Columns.playbackCoverage]

    #expect(currentTime == CMTime.seconds(15))
    #expect(maxPlayback == CMTime.seconds(15))
    #expect(lastPlayed != nil)
    if let lastPlayed {
      #expect(abs(lastPlayed.timeIntervalSince(now)) < 1.0)
    }
    #expect(bitmap != nil)

    let coverage = try await loadCoverage(for: episode.id, durationSeconds: 60)
    #expect(coverage?.coveredSeconds == 15)
  }

  @Test("re-listening the same range does not double-count coverage")
  func reListenNoDoubleCount() async throws {
    let episode = try await insertEpisode(durationSeconds: 60)

    try await repo.updatePlayback(
      episode.id,
      currentTime: CMTime.seconds(30),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )
    let firstPass = try await loadCoverage(for: episode.id, durationSeconds: 60)
    #expect(firstPass?.coveredSeconds == 30)

    // User scrubbed back to 0 and replayed [0, 30) — same bits, no growth.
    try await repo.updatePlayback(
      episode.id,
      currentTime: CMTime.seconds(30),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )
    let secondPass = try await loadCoverage(for: episode.id, durationSeconds: 60)
    #expect(secondPass?.coveredSeconds == 30)
  }

  @Test("disjoint playback ranges accumulate")
  func disjointRangesAccumulate() async throws {
    let episode = try await insertEpisode(durationSeconds: 60)

    try await repo.updatePlayback(
      episode.id,
      currentTime: CMTime.seconds(15),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )
    try await repo.updatePlayback(
      episode.id,
      currentTime: CMTime.seconds(45),
      playedFrom: CMTime.seconds(30),
      now: Date()
    )

    let coverage = try await loadCoverage(for: episode.id, durationSeconds: 60)
    #expect(coverage?.coveredSeconds == 30)
  }

  @Test("backward playedFrom (post-seek) leaves bitmap untouched but updates currentTime")
  func backwardPlayedFromNoBitmapChange() async throws {
    let episode = try await insertEpisode(durationSeconds: 60)

    try await repo.updatePlayback(
      episode.id,
      currentTime: CMTime.seconds(30),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )
    let originalBytes = try await loadCoverage(for: episode.id, durationSeconds: 60)?.bytes

    // Seek backward: playedFrom > currentTime. No new range to mark.
    try await repo.updatePlayback(
      episode.id,
      currentTime: CMTime.seconds(10),
      playedFrom: CMTime.seconds(30),
      now: Date()
    )

    let after = try await loadCoverage(for: episode.id, durationSeconds: 60)
    #expect(after?.bytes == originalBytes)

    let row = try await repo.db.read { db in
      try Row.fetchOne(
        db,
        Episode.withID(episode.id).select(Episode.Columns.currentTime)
      )
    }
    #expect((row?[Episode.Columns.currentTime] as CMTime?) == CMTime.seconds(10))
  }

  @Test("zero-duration episode skips bitmap write but still updates currentTime")
  func zeroDurationSkipsBitmap() async throws {
    let episode = try await insertEpisode(durationSeconds: 0)

    try await repo.updatePlayback(
      episode.id,
      currentTime: CMTime.seconds(15),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )

    let row = try await repo.db.read { db in
      try Row.fetchOne(
        db,
        Episode.withID(episode.id)
          .select(Episode.Columns.currentTime, Episode.Columns.playbackCoverage)
      )
    }
    let unwrapped = try #require(row)
    #expect((unwrapped[Episode.Columns.currentTime] as CMTime?) == CMTime.seconds(15))
    #expect((unwrapped[Episode.Columns.playbackCoverage] as Data?) == nil)
  }

  @Test("missing episode returns false")
  func missingEpisodeReturnsFalse() async throws {
    let result = try await repo.updatePlayback(
      Episode.ID(rawValue: 999_999),
      currentTime: CMTime.seconds(10),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )
    #expect(result == false)
  }

  @Test("maxPlaybackTime advances but never regresses")
  func maxPlaybackTimeAdvances() async throws {
    let episode = try await insertEpisode(durationSeconds: 300)

    try await repo.updatePlayback(
      episode.id,
      currentTime: CMTime.seconds(120),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )
    try await repo.updatePlayback(
      episode.id,
      currentTime: CMTime.seconds(45),
      playedFrom: CMTime.seconds(120),
      now: Date()
    )

    let row = try await repo.db.read { db in
      try Row.fetchOne(
        db,
        Episode.withID(episode.id)
          .select(Episode.Columns.currentTime, Episode.Columns.maxPlaybackTime)
      )
    }
    let unwrapped = try #require(row)
    #expect((unwrapped[Episode.Columns.currentTime] as CMTime?) == CMTime.seconds(45))
    #expect((unwrapped[Episode.Columns.maxPlaybackTime] as CMTime?) == CMTime.seconds(120))
  }
}
