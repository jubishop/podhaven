// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

// The candidate-set observation must not wake on per-checkpoint playback
// writes: candidate membership reads boundary-flipped columns, never the
// per-tick playback columns (currentTime, maxPlaybackTime, lastPlayedDate,
// playbackCoverage). Genuine membership changes — start, finish, queue,
// rate — must still re-emit promptly.
@Suite("of Observatory candidate episode observation tests", .container)
actor ObservatoryCandidateEpisodesTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.repo) private var repo

  // MARK: - Helpers

  @discardableResult
  private func createPodcastEpisode() async throws -> PodcastEpisode {
    let podcastEpisodes = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisode: try Create.unsavedEpisode()
      )
    ])
    return podcastEpisodes.first!
  }

  private func insertEmbedding(for episodeID: Episode.ID) async throws {
    try await recommendationRepo.upsertEmbeddings([
      UnsavedEpisodeEmbedding(
        episodeId: episodeID,
        vector: UnsavedEpisodeEmbedding.vectorData(from: [1.0, 0.0, 0.0]),
        sourceHash: "test-hash",
        embeddingRevision: 1,
        dimension: 3,
        verificationDate: Date()
      )
    ])
  }

  private func observeCandidateIDs() -> ThreadSafe<Set<Episode.ID>?> {
    let candidateIDs = ThreadSafe<Set<Episode.ID>?>(nil)
    let observation = observatory.embeddedCandidateEpisodes(filter: Episode.candidate)
    Task {
      for try await candidates in observation {
        candidateIDs(Set(candidates.map(\.id)))
      }
    }
    return candidateIDs
  }

  // MARK: - Playback Ticks

  @Test("playback tick bursts do not wake the candidate observation")
  func playbackTicksDoNotWakeObservation() async throws {
    let stays = try await createPodcastEpisode()
    try await insertEmbedding(for: stays.episode.id)
    let played = try await createPodcastEpisode()
    try await insertEmbedding(for: played.episode.id)
    // Pre-start playback so the burst below never crosses the
    // unstarted/started boundary and the candidate set stays stable.
    _ = try await repo.updatePlayback(
      played.episode.id,
      currentTime: CMTime.seconds(1),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )

    // Counts fetch executions, not emissions: a wake re-runs the fetch on a
    // reader even when `removeDuplicates()` swallows the unchanged value.
    let fetches = ThreadSafe<Int>(0)
    let emissions = Counter()
    let reader = appDB.reader
    Task {
      let observation = reader.observe { db -> [CandidateEpisode] in
        fetches { $0 += 1 }
        return
          try CandidateEpisode
          .joining(required: CandidateEpisode.podcast)
          .filter(Episode.candidate && Episode.hasEmbedding)
          .fetchAll(db)
      }
      for try await _ in observation {
        await emissions.increment()
      }
    }
    try await emissions.wait(for: 1)

    for second in stride(from: 3, through: 30, by: 3) {
      _ = try await repo.updatePlayback(
        played.episode.id,
        currentTime: CMTime.seconds(Double(second)),
        playedFrom: CMTime.seconds(Double(second - 3)),
        now: Date()
      )
    }

    // Drain write: finishing `stays` changes candidate membership, so its
    // emission proves every earlier tick commit has been processed.
    _ = try await repo.markFinished(stays.episode.id)
    try await emissions.wait(for: 2)

    #expect(fetches() == 2, "playback ticks woke the candidate observation (\(fetches()) fetches)")
  }

  @Test("updatePlayback bursts do not re-emit the candidate set")
  func updatePlaybackDoesNotReEmitCandidates() async throws {
    let stays = try await createPodcastEpisode()
    try await insertEmbedding(for: stays.episode.id)
    let played = try await createPodcastEpisode()
    try await insertEmbedding(for: played.episode.id)
    _ = try await repo.updatePlayback(
      played.episode.id,
      currentTime: CMTime.seconds(1),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )

    let emissions = Counter()
    let observation = observatory.embeddedCandidateEpisodes(filter: Episode.candidate)
    Task {
      for try await _ in observation {
        await emissions.increment()
      }
    }
    try await emissions.wait(for: 1)

    for second in stride(from: 3, through: 30, by: 3) {
      _ = try await repo.updatePlayback(
        played.episode.id,
        currentTime: CMTime.seconds(Double(second)),
        playedFrom: CMTime.seconds(Double(second - 3)),
        now: Date()
      )
    }

    _ = try await repo.markFinished(stays.episode.id)
    try await emissions.wait(for: 2)
    #expect(await emissions.maxValue == 2)
  }

  // MARK: - Membership Boundaries

  @Test("starting playback drops the episode; seeking back to zero restores it")
  func playbackBoundaryUpdatesCandidateSet() async throws {
    let played = try await createPodcastEpisode()
    try await insertEmbedding(for: played.episode.id)

    let candidateIDs = observeCandidateIDs()
    try await Wait.until(
      { candidateIDs() == Set([played.episode.id]) },
      { "Expected initial candidate emission, got \(String(describing: candidateIDs()))" }
    )

    _ = try await repo.updatePlayback(
      played.episode.id,
      currentTime: CMTime.seconds(3),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )
    try await Wait.until(
      { candidateIDs() == Set([]) },
      { "Expected started episode to leave the candidate set" }
    )

    _ = try await repo.updateCurrentTime(played.episode.id, currentTime: CMTime.seconds(0))
    try await Wait.until(
      { candidateIDs() == Set([played.episode.id]) },
      { "Expected reset episode to rejoin the candidate set" }
    )
  }

  @Test("queueing and rating changes update the candidate set promptly")
  func userActionsUpdateCandidateSet() async throws {
    let rated = try await createPodcastEpisode()
    try await insertEmbedding(for: rated.episode.id)
    let queued = try await createPodcastEpisode()
    try await insertEmbedding(for: queued.episode.id)
    let both = Set([rated.episode.id, queued.episode.id])

    let candidateIDs = observeCandidateIDs()
    try await Wait.until(
      { candidateIDs() == both },
      { "Expected initial candidate emission, got \(String(describing: candidateIDs()))" }
    )

    _ = try await repo.updateRating(rated.episode.id, rating: .liked)
    try await Wait.until(
      { candidateIDs() == Set([queued.episode.id]) },
      { "Expected rated episode to leave the candidate set" }
    )

    try await queue.unshift(queued.episode.id)
    try await Wait.until(
      { candidateIDs() == Set([]) },
      { "Expected queued episode to leave the candidate set" }
    )

    try await queue.dequeue(queued.episode.id)
    _ = try await repo.updateRating(rated.episode.id, rating: nil)
    try await Wait.until(
      { candidateIDs() == both },
      { "Expected unqueued and unrated episodes to rejoin the candidate set" }
    )
  }

  @Test("a newly embedded episode joins the candidate set")
  func newEmbeddingUpdatesCandidateSet() async throws {
    let embedded = try await createPodcastEpisode()
    try await insertEmbedding(for: embedded.episode.id)
    let unembedded = try await createPodcastEpisode()

    let candidateIDs = observeCandidateIDs()
    try await Wait.until(
      { candidateIDs() == Set([embedded.episode.id]) },
      { "Expected initial candidate emission, got \(String(describing: candidateIDs()))" }
    )

    try await insertEmbedding(for: unembedded.episode.id)
    try await Wait.until(
      { candidateIDs() == Set([embedded.episode.id, unembedded.episode.id]) },
      { "Expected newly embedded episode to join the candidate set" }
    )
  }
}
