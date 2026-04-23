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
  @DynamicInjected(\.repo) private var repo

  // MARK: - Helpers

  private func createPodcastEpisode(
    title: String = String.random(),
    description: String? = nil,
    podcastDescription: String = String.random(),
    rating: EpisodeRating? = nil,
    finishDate: Date? = nil,
    currentTime: CMTime? = nil,
    queueOrder: Int? = nil
  ) async throws -> PodcastEpisode {
    let podcastEpisodes = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(description: podcastDescription),
        unsavedEpisode: try Create.unsavedEpisode(
          title: title,
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
      dimension: 3
    )
    try await repo.upsertEmbedding(unsaved)

    if backdated {
      // Push creationDate into the past so trigger-updated contentUpdatedAt is clearly newer
      try await appDB.db.write { db in
        try db.execute(
          sql: """
            UPDATE episodeEmbedding SET creationDate = datetime('now', '-1 hour')
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

    let result = try await repo.episodesNeedingEmbeddings(revision: 1)
    #expect(result.contains(pe.episode.id))
  }

  @Test("includes finished episodes without embeddings")
  func finishedEpisodesIncluded() async throws {
    let pe = try await createPodcastEpisode(finishDate: Date())

    let result = try await repo.episodesNeedingEmbeddings(revision: 1)
    #expect(result.contains(pe.episode.id))
  }

  @Test("includes unstarted, unfinished, unrated, unqueued episodes")
  func candidateEpisodesIncluded() async throws {
    let pe = try await createPodcastEpisode()

    let result = try await repo.episodesNeedingEmbeddings(revision: 1)
    #expect(result.contains(pe.episode.id))
  }

  @Test("excludes queued episodes that are otherwise candidates")
  func queuedEpisodesExcluded() async throws {
    let pe = try await createPodcastEpisode(queueOrder: 1)

    let result = try await repo.episodesNeedingEmbeddings(revision: 1)
    #expect(!result.contains(pe.episode.id))
  }

  @Test("excludes started episodes that are otherwise candidates")
  func startedEpisodesExcluded() async throws {
    let pe = try await createPodcastEpisode(currentTime: CMTime(seconds: 60, preferredTimescale: 1))

    let result = try await repo.episodesNeedingEmbeddings(revision: 1)
    #expect(!result.contains(pe.episode.id))
  }

  @Test("excludes episodes with fresh embeddings at correct revision")
  func freshEmbeddingsExcluded() async throws {
    let pe = try await createPodcastEpisode(rating: .liked)
    try await insertEmbedding(for: pe.episode.id, revision: 1)

    let result = try await repo.episodesNeedingEmbeddings(revision: 1)
    #expect(!result.contains(pe.episode.id))
  }

  @Test("includes episodes with wrong embedding revision")
  func wrongRevisionIncluded() async throws {
    let pe = try await createPodcastEpisode(rating: .liked)
    try await insertEmbedding(for: pe.episode.id, revision: 1)

    let result = try await repo.episodesNeedingEmbeddings(revision: 2)
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

    let result = try await repo.episodesNeedingEmbeddings(revision: 1)
    #expect(result.contains(pe.episode.id))
  }

  @Test("signal episodes ordered before candidate episodes")
  func signalEpisodesFirst() async throws {
    // Create candidate first (unstarted, unfinished, unrated, unqueued)
    let candidate = try await createPodcastEpisode()
    // Create signal second (rated)
    let signal = try await createPodcastEpisode(rating: .loved)

    let result = try await repo.episodesNeedingEmbeddings(revision: 1)

    let signalIndex = result.firstIndex(of: signal.episode.id)
    let candidateIndex = result.firstIndex(of: candidate.episode.id)

    let unwrappedSignal = try #require(signalIndex)
    let unwrappedCandidate = try #require(candidateIndex)
    #expect(unwrappedSignal < unwrappedCandidate)
  }

  @Test("returns empty when no episodes exist")
  func emptyWhenNoEpisodes() async throws {
    let result = try await repo.episodesNeedingEmbeddings(revision: 1)
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

    let result = try await repo.episodesNeedingEmbeddings(revision: 1)
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

    let result = try await repo.episodesNeedingEmbeddings(revision: 1)
    #expect(result.contains(pe.episode.id))
  }
}
