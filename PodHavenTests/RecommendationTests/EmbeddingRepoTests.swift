// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("Embedding repo tests", .container)
class EmbeddingRepoTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.repo) private var repo

  // MARK: - Helpers

  private func createPodcastEpisode(
    title: String = String.random(),
    description: String? = nil,
    podcastDescription: String = String.random(),
    rating: EpisodeRating? = nil,
    pubDate: Date? = Date(),
    finishDate: Date? = nil,
    currentTime: CMTime? = nil,
    queueOrder: Int? = nil
  ) async throws -> PodcastEpisode {
    let podcastEpisodes = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(description: podcastDescription),
        unsavedEpisode: try Create.unsavedEpisode(
          title: title,
          pubDate: pubDate,
          description: description,
          finishDate: finishDate,
          currentTime: currentTime,
          queueOrder: queueOrder,
          rating: rating
        )
      )
    ])
    return podcastEpisodes.first!
  }

  private func insertEmbedding(
    for episodeID: Episode.ID,
    revision: Int = 1,
    backdated: Bool = false
  ) async throws {
    let unsaved = UnsavedEpisodeEmbedding(
      episodeId: episodeID,
      vector: UnsavedEpisodeEmbedding.vectorData(from: [1.0, 0.0, 0.0]),
      sourceHash: "test-hash",
      embeddingRevision: revision,
      dimension: 3,
      verificationDate: Date()
    )
    try await recommendationRepo.upsertEmbeddings([unsaved])

    if backdated {
      // Push verificationDate into the past so trigger-updated contentUpdatedAt is clearly newer
      try await appDB.db.write { db in
        try db.execute(
          sql: """
            UPDATE episodeEmbedding SET verificationDate = datetime('now', '-1 hour')
            WHERE episodeId = ?
            """,
          arguments: [episodeID]
        )
      }
    }
  }

  private func contentUpdatedAt(forEpisode episodeID: Episode.ID) async throws -> String? {
    try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM episode WHERE id = ?",
        arguments: [episodeID]
      )
    }
  }

  private func contentUpdatedAt(forPodcast podcastID: Podcast.ID) async throws -> String? {
    try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM podcast WHERE id = ?",
        arguments: [podcastID]
      )
    }
  }

  // MARK: - Trigger Behavior Tests

  @Test("episode trigger updates contentUpdatedAt when title changes")
  func episodeTitleTrigger() async throws {
    let pe = try await createPodcastEpisode(title: "Original Title")
    let before = try await contentUpdatedAt(forEpisode: pe.episode.id)
    #expect(before != nil)

    _ = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(
        unsavedPodcast: try pe.podcast.toOriginalUnsavedPodcast(),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: pe.episode.unsaved.guid,
          mediaURL: pe.episode.unsaved.mediaURL,
          title: "Changed Title"
        )
      )
    ])

    let after = try await contentUpdatedAt(forEpisode: pe.episode.id)
    #expect(after != nil)
    #expect(after! >= before!)
  }

  @Test("episode trigger updates contentUpdatedAt when description changes")
  func episodeDescriptionTrigger() async throws {
    let pe = try await createPodcastEpisode(
      title: "Trigger Test",
      description: "Original description"
    )
    let before = try await contentUpdatedAt(forEpisode: pe.episode.id)

    _ = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(
        unsavedPodcast: try pe.podcast.toOriginalUnsavedPodcast(),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: pe.episode.unsaved.guid,
          mediaURL: pe.episode.unsaved.mediaURL,
          title: "Trigger Test",
          description: "Changed description"
        )
      )
    ])

    let after = try await contentUpdatedAt(forEpisode: pe.episode.id)
    #expect(after! >= before!)
  }

  @Test("episode trigger does not fire when non-content fields change")
  func episodeTriggerIgnoresNonContent() async throws {
    let pe = try await createPodcastEpisode(title: "Same Title", description: "Same Description")
    let before = try await contentUpdatedAt(forEpisode: pe.episode.id)

    // Re-upsert same title/description — trigger should not fire
    _ = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(
        unsavedPodcast: try pe.podcast.toOriginalUnsavedPodcast(),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: pe.episode.unsaved.guid,
          mediaURL: pe.episode.unsaved.mediaURL,
          title: "Same Title",
          description: "Same Description"
        )
      )
    ])

    let after = try await contentUpdatedAt(forEpisode: pe.episode.id)
    #expect(after == before)
  }

  @Test("podcast trigger updates contentUpdatedAt when description changes")
  func podcastDescriptionTrigger() async throws {
    let pe = try await createPodcastEpisode(podcastDescription: "Original podcast desc")
    let before = try await contentUpdatedAt(forPodcast: pe.podcast.id)

    _ = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: pe.podcast.feedURL,
          title: pe.podcast.title,
          image: pe.podcast.image,
          description: "Changed podcast desc",
          link: pe.podcast.link
        ),
        unsavedEpisode: try pe.episode.toOriginalUnsavedEpisode()
      )
    ])

    let after = try await contentUpdatedAt(forPodcast: pe.podcast.id)
    #expect(after! >= before!)
  }

  @Test("podcast trigger does not fire when description is unchanged")
  func podcastTriggerIgnoresUnchanged() async throws {
    let pe = try await createPodcastEpisode(podcastDescription: "Stable desc")
    let before = try await contentUpdatedAt(forPodcast: pe.podcast.id)

    _ = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: pe.podcast.feedURL,
          title: pe.podcast.title,
          image: pe.podcast.image,
          description: "Stable desc",
          link: pe.podcast.link
        ),
        unsavedEpisode: try pe.episode.toOriginalUnsavedEpisode()
      )
    ])

    let after = try await contentUpdatedAt(forPodcast: pe.podcast.id)
    #expect(after == before)
  }

  // MARK: - episodesNeedingEmbeddings Tests

  @Test("includes rated episodes without embeddings")
  func ratedEpisodesIncluded() async throws {
    let pe = try await createPodcastEpisode(rating: .loved)

    let result = try await recommendationRepo.episodesNeedingEmbeddings(revision: 1)
    #expect(result.contains(pe.episode.id))
  }

  @Test("includes finished episodes that have no rating and no playback bitmap")
  func finishedNoBitmapIncluded() async throws {
    let pe = try await createPodcastEpisode(finishDate: Date())

    let result = try await recommendationRepo.episodesNeedingEmbeddings(revision: 1)
    #expect(result.contains(pe.episode.id))
  }

  @Test("includes episodes with a playback bitmap even after finish")
  func playedThenFinishedIncluded() async throws {
    let pe = try await createPodcastEpisode()
    try await repo.updateDuration(pe.episode.id, duration: CMTime.seconds(300))
    try await repo.updatePlayback(
      pe.episode.id,
      currentTime: CMTime.seconds(60),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )
    try await repo.markFinished(pe.episode.id)

    let result = try await recommendationRepo.episodesNeedingEmbeddings(revision: 1)
    #expect(result.contains(pe.episode.id))
  }

  @Test("includes unstarted, unfinished, unrated, unqueued episodes")
  func candidateEpisodesIncluded() async throws {
    let pe = try await createPodcastEpisode()

    let result = try await recommendationRepo.episodesNeedingEmbeddings(revision: 1)
    #expect(result.contains(pe.episode.id))
  }

  @Test("includes queued episodes")
  func queuedEpisodesIncluded() async throws {
    let pe = try await createPodcastEpisode(queueOrder: 1)

    let result = try await recommendationRepo.episodesNeedingEmbeddings(revision: 1)
    #expect(result.contains(pe.episode.id))
  }

  @Test("includes started episodes")
  func startedEpisodesIncluded() async throws {
    let pe = try await createPodcastEpisode(currentTime: CMTime(seconds: 60, preferredTimescale: 1))

    let result = try await recommendationRepo.episodesNeedingEmbeddings(revision: 1)
    #expect(result.contains(pe.episode.id))
  }

  @Test("excludes episodes with fresh embeddings at correct revision")
  func freshEmbeddingsExcluded() async throws {
    let pe = try await createPodcastEpisode(rating: .liked)
    try await insertEmbedding(for: pe.episode.id, revision: 1)

    let result = try await recommendationRepo.episodesNeedingEmbeddings(revision: 1)
    #expect(!result.contains(pe.episode.id))
  }

  @Test("includes episodes with wrong embedding revision")
  func wrongRevisionIncluded() async throws {
    let pe = try await createPodcastEpisode(rating: .liked)
    try await insertEmbedding(for: pe.episode.id, revision: 1)

    let result = try await recommendationRepo.episodesNeedingEmbeddings(revision: 2)
    #expect(result.contains(pe.episode.id))
  }

  @Test("includes episodes whose content updated after embedding creation")
  func staleContentIncluded() async throws {
    let pe = try await createPodcastEpisode(
      title: "Original",
      description: "Original desc",
      rating: .liked
    )
    try await insertEmbedding(for: pe.episode.id, revision: 1, backdated: true)

    // Trigger contentUpdatedAt by changing title
    _ = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(
        unsavedPodcast: try pe.podcast.toOriginalUnsavedPodcast(),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: pe.episode.unsaved.guid,
          mediaURL: pe.episode.unsaved.mediaURL,
          title: "Updated Title",
          description: "Original desc"
        )
      )
    ])

    let result = try await recommendationRepo.episodesNeedingEmbeddings(revision: 1)
    #expect(result.contains(pe.episode.id))
  }

  @Test("newer episodes ordered before older episodes")
  func newerPubDateFirst() async throws {
    let older = try await createPodcastEpisode(pubDate: Date(timeIntervalSince1970: 1_000_000))
    let newer = try await createPodcastEpisode(pubDate: Date(timeIntervalSince1970: 2_000_000))

    let result = try await recommendationRepo.episodesNeedingEmbeddings(revision: 1)

    let newerIndex = try #require(result.firstIndex(of: newer.episode.id))
    let olderIndex = try #require(result.firstIndex(of: older.episode.id))
    #expect(newerIndex < olderIndex)
  }

  @Test("returns empty when no episodes exist")
  func emptyWhenNoEpisodes() async throws {
    let result = try await recommendationRepo.episodesNeedingEmbeddings(revision: 1)
    #expect(result.isEmpty)
  }

  @Test("empty podcast description becoming populated invalidates embeddings")
  func emptyToPopulatedPodcastDescription() async throws {
    let pe = try await createPodcastEpisode(
      podcastDescription: "",
      rating: .liked
    )
    try await insertEmbedding(for: pe.episode.id, revision: 1, backdated: true)

    // Populate the previously-empty podcast description. The podcast trigger
    // should fire on "" → "Now has content", pushing contentUpdatedAt past the
    // backdated embedding creationDate.
    _ = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: pe.podcast.feedURL,
          title: pe.podcast.title,
          image: pe.podcast.image,
          description: "Now has content",
          link: pe.podcast.link
        ),
        unsavedEpisode: try pe.episode.toOriginalUnsavedEpisode()
      )
    ])

    let result = try await recommendationRepo.episodesNeedingEmbeddings(revision: 1)
    #expect(result.contains(pe.episode.id))
  }

  @Test("includes episodes whose podcast content updated after embedding creation")
  func podcastContentStaleIncluded() async throws {
    let pe = try await createPodcastEpisode(
      podcastDescription: "Original podcast desc",
      rating: .liked
    )
    try await insertEmbedding(for: pe.episode.id, revision: 1, backdated: true)

    // Trigger podcast contentUpdatedAt by changing podcast description
    _ = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: pe.podcast.feedURL,
          title: pe.podcast.title,
          image: pe.podcast.image,
          description: "Changed podcast desc",
          link: pe.podcast.link
        ),
        unsavedEpisode: try pe.episode.toOriginalUnsavedEpisode()
      )
    ])

    let result = try await recommendationRepo.episodesNeedingEmbeddings(revision: 1)
    #expect(result.contains(pe.episode.id))
  }

  // MARK: - hasEmbeddings Tests

  @Test("hasEmbeddings returns false on empty DB")
  func hasEmbeddingsEmpty() async throws {
    #expect(try await recommendationRepo.hasEmbeddings() == false)
  }

  @Test("hasEmbeddings returns false with episodes but no embeddings")
  func hasEmbeddingsEpisodesOnly() async throws {
    _ = try await createPodcastEpisode()
    #expect(try await recommendationRepo.hasEmbeddings() == false)
  }

  @Test("hasEmbeddings returns true after upsertEmbeddings")
  func hasEmbeddingsAfterUpsert() async throws {
    let pe = try await createPodcastEpisode()
    try await insertEmbedding(for: pe.episode.id)
    #expect(try await recommendationRepo.hasEmbeddings() == true)
  }

  // MARK: - allCandidateEpisodes Tests

  @Test("allCandidateEpisodes returns unrated unstarted unfinished unqueued episodes")
  func candidatesIncluded() async throws {
    let pe = try await createPodcastEpisode()
    try await insertEmbedding(for: pe.episode.id)
    let result = try await recommendationRepo.allCandidateEpisodes(excluding: nil)
    #expect(result.map(\.id).contains(pe.episode.id))
  }

  @Test("allCandidateEpisodes omits rated episodes")
  func candidatesExcludeRated() async throws {
    let pe = try await createPodcastEpisode(rating: .loved)
    try await insertEmbedding(for: pe.episode.id)
    let result = try await recommendationRepo.allCandidateEpisodes(excluding: nil)
    #expect(!result.map(\.id).contains(pe.episode.id))
  }

  @Test("allCandidateEpisodes omits finished episodes")
  func candidatesExcludeFinished() async throws {
    let pe = try await createPodcastEpisode(finishDate: Date())
    try await insertEmbedding(for: pe.episode.id)
    let result = try await recommendationRepo.allCandidateEpisodes(excluding: nil)
    #expect(!result.map(\.id).contains(pe.episode.id))
  }

  @Test("allCandidateEpisodes omits queued episodes")
  func candidatesExcludeQueued() async throws {
    let pe = try await createPodcastEpisode(queueOrder: 1)
    try await insertEmbedding(for: pe.episode.id)
    let result = try await recommendationRepo.allCandidateEpisodes(excluding: nil)
    #expect(!result.map(\.id).contains(pe.episode.id))
  }

  @Test("allCandidateEpisodes omits started episodes")
  func candidatesExcludeStarted() async throws {
    let pe = try await createPodcastEpisode(
      currentTime: CMTime(seconds: 60, preferredTimescale: 1)
    )
    try await insertEmbedding(for: pe.episode.id)
    let result = try await recommendationRepo.allCandidateEpisodes(excluding: nil)
    #expect(!result.map(\.id).contains(pe.episode.id))
  }

  @Test("allCandidateEpisodes respects excluding parameter")
  func candidatesRespectExclusion() async throws {
    let excluded = try await createPodcastEpisode()
    try await insertEmbedding(for: excluded.episode.id)
    let kept = try await createPodcastEpisode()
    try await insertEmbedding(for: kept.episode.id)
    let result = try await recommendationRepo.allCandidateEpisodes(excluding: excluded.episode.id)
    let ids = result.map(\.id)
    #expect(!ids.contains(excluded.episode.id))
    #expect(ids.contains(kept.episode.id))
  }

  @Test("allCandidateEpisodes omits episodes without an embedding row")
  func candidatesExcludeUnembedded() async throws {
    let pe = try await createPodcastEpisode()
    let result = try await recommendationRepo.allCandidateEpisodes(excluding: nil)
    #expect(!result.map(\.id).contains(pe.episode.id))
  }

  // MARK: - Mid-Delete FK Race Tests

  private func unsavedEmbedding(for episodeID: Episode.ID) -> UnsavedEpisodeEmbedding {
    UnsavedEpisodeEmbedding(
      episodeId: episodeID,
      vector: UnsavedEpisodeEmbedding.vectorData(from: [1.0, 0.0, 0.0]),
      sourceHash: "test-hash",
      embeddingRevision: 1,
      dimension: 3,
      verificationDate: Date()
    )
  }

  @Test("upsertEmbeddings skips an episode deleted mid-flight instead of failing")
  func upsertEmbeddingsSkipsDeletedEpisode() async throws {
    let pe = try await createPodcastEpisode()
    let unsaved = unsavedEmbedding(for: pe.episode.id)

    // The podcast — and, via cascade, its episode — is gone before the
    // embedding lands, mirroring a delete that races a foreground embedding.
    try await repo.deletePodcast(pe.podcast.id)

    try await recommendationRepo.upsertEmbeddings([unsaved])

    #expect(try await recommendationRepo.embedding(for: pe.episode.id) == nil)
  }

  @Test("upsertEmbeddings writes live episodes when a sibling was deleted mid-flight")
  func upsertEmbeddingsWritesLiveAlongsideDeleted() async throws {
    let live = try await createPodcastEpisode()
    let doomed = try await createPodcastEpisode()
    let batch = [
      unsavedEmbedding(for: live.episode.id),
      unsavedEmbedding(for: doomed.episode.id),
    ]

    try await repo.deletePodcast(doomed.podcast.id)

    try await recommendationRepo.upsertEmbeddings(batch)

    #expect(try await recommendationRepo.embedding(for: live.episode.id) != nil)
    #expect(try await recommendationRepo.embedding(for: doomed.episode.id) == nil)
  }

  @Test("upsertPodcastEmbeddings skips a podcast deleted mid-flight instead of failing")
  func upsertPodcastEmbeddingsSkipsDeletedPodcast() async throws {
    let pe = try await createPodcastEpisode()
    let unsaved = UnsavedPodcastEmbedding(
      podcastId: pe.podcast.id,
      vector: UnsavedPodcastEmbedding.vectorData(from: [1.0, 0.0, 0.0]),
      sourceHash: "test-hash",
      embeddingRevision: 1,
      dimension: 3
    )

    try await repo.deletePodcast(pe.podcast.id)

    try await recommendationRepo.upsertPodcastEmbeddings([unsaved])

    #expect(try await recommendationRepo.podcastEmbedding(for: pe.podcast.id) == nil)
  }
}
