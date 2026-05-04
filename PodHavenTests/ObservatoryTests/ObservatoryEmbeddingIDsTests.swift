// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Observatory episodeEmbeddingIDs tests", .container)
actor ObservatoryEmbeddingIDsTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.appDB) private var appDB

  // MARK: - Helpers

  private func insertPodcast(title: String = String.random()) async throws -> Podcast {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: title),
        unsavedEpisodes: []
      )
    )
    return series.podcast
  }

  private func upsertEpisode(
    podcast: Podcast,
    title: String = String.random()
  ) async throws -> Episode {
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: podcast.feedURL,
      title: podcast.title,
      image: podcast.image,
      description: podcast.description
    )
    let unsavedEpisode = try Create.unsavedEpisode(
      title: title,
      pubDate: Date(),
      duration: CMTime(seconds: 1800, preferredTimescale: 1)
    )
    let podcastEpisodes = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: unsavedEpisode)
    ])
    return try #require(podcastEpisodes.first?.episode)
  }

  private func upsertEmbedding(
    for episode: Episode,
    vector: [Float] = [1, 0, 0],
    sourceHash: String? = nil
  ) async throws {
    let data = UnsavedEpisodeEmbedding.vectorData(from: vector)
    try await repo.upsertEmbedding(
      UnsavedEpisodeEmbedding(
        episodeId: episode.id,
        vector: data,
        sourceHash: sourceHash ?? "hash-\(episode.id)",
        embeddingRevision: 1,
        dimension: vector.count
      )
    )
  }

  // MARK: - Tracked Region

  // Direct verification that the fetch reads exactly one column from one
  // table and nothing joined. Stronger than emission-counting, because
  // `.removeDuplicates()` can mask a too-wide region by suppressing
  // unchanged emissions even when GRDB re-fetched.
  @Test("episodeEmbeddingIDs tracks only episodeEmbedding(episodeId)")
  func trackedRegionIsScopedToEmbeddingTable() async throws {
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
    let db = repo.db

    let region = try await db.read { db in
      try EpisodeEmbedding
        .select(EpisodeEmbedding.Columns.episodeId, as: Episode.ID.self)
        .databaseRegion(db)
    }

    // Episode columns must NOT be in the tracked region. If a future edit
    // accidentally adds `.including(required: EpisodeEmbedding.episode)` or
    // joins the Episode table, one of these will start firing the
    // observation on every playback tick / refresh tick. We sweep every
    // column on Episode so the test catches any future drift, not just the
    // hot ones.
    let episodeColumns = [
      "id", "podcastId", "guid", "mediaURL", "title", "pubDate", "duration",
      "description", "image", "link", "creationDate", "queueOrder",
      "queueDate", "saveInCache", "cachedFilename", "downloadTaskID",
      "rating", "ratingDate", "finishDate", "currentTime", "maxPlaybackTime",
      "playbackCoverage", "lastPlayedDate", "contentUpdatedAt",
    ]
    for column in episodeColumns {
      #expect(
        !region.isModified(
          byEventsOfKind: .update(tableName: "episode", columnNames: [column])
        ),
        "episodeEmbeddingIDs region must not track episode column: \(column)"
      )
    }

    // Podcast columns must NOT be in the tracked region either.
    let podcastColumns = [
      "id", "feedURL", "title", "description", "image", "link",
      "iTunesID", "subscriptionDate", "lastUpdate", "notifyNewEpisodes",
      "queueAllEpisodes", "cacheAllEpisodes", "defaultPlaybackRate",
      "freshnessCadence",
    ]
    for column in podcastColumns {
      #expect(
        !region.isModified(
          byEventsOfKind: .update(tableName: "podcast", columnNames: [column])
        ),
        "episodeEmbeddingIDs region must not track podcast column: \(column)"
      )
    }

    // The episodeId column on episodeEmbedding is the projection — must
    // wake the observation.
    #expect(
      region.isModified(
        byEventsOfKind: .update(tableName: "episodeEmbedding", columnNames: ["episodeId"])
      ),
      "episodeEmbeddingIDs region must track episodeEmbedding.episodeId"
    )
  }

  // MARK: - Behavior

  @Test("emits empty set when no embeddings exist")
  func emptyState() async throws {
    let ids = try await observatory.episodeEmbeddingIDs().get()
    #expect(ids.isEmpty)
  }

  @Test("emits the set of episodeIds with embeddings")
  func emitsEmbeddedSet() async throws {
    let podcast = try await insertPodcast()
    let a = try await upsertEpisode(podcast: podcast, title: "A")
    let b = try await upsertEpisode(podcast: podcast, title: "B")
    let unembedded = try await upsertEpisode(podcast: podcast, title: "Unembedded")
    try await upsertEmbedding(for: a)
    try await upsertEmbedding(for: b)

    let ids = try await observatory.episodeEmbeddingIDs().get()
    #expect(ids == [a.id, b.id])
    #expect(!ids.contains(unembedded.id))
  }

  @Test("re-emits when an embedding is inserted")
  func reEmitsOnInsert() async throws {
    let podcast = try await insertPodcast()
    let episode = try await upsertEpisode(podcast: podcast)

    let setSize = Counter()
    Task {
      for try await ids in observatory.episodeEmbeddingIDs() {
        await setSize(ids.count)
      }
    }
    try await Wait.until(
      { await setSize.value == 0 },
      { "Expected initial empty emission" }
    )

    try await upsertEmbedding(for: episode)
    try await Wait.until(
      { await setSize.value == 1 },
      { "Expected re-emission with one embedding, got \(await setSize.value)" }
    )
  }

  @Test("re-emits when an embedding is deleted")
  func reEmitsOnDelete() async throws {
    let podcast = try await insertPodcast()
    let episode = try await upsertEpisode(podcast: podcast)
    try await upsertEmbedding(for: episode)

    let setSize = Counter()
    Task {
      for try await ids in observatory.episodeEmbeddingIDs() {
        await setSize(ids.count)
      }
    }
    try await Wait.until(
      { await setSize.value == 1 },
      { "Expected initial emission with one embedding" }
    )

    try await appDB.db.write { db in
      try db.execute(
        sql: "DELETE FROM episodeEmbedding WHERE episodeId = ?",
        arguments: [episode.id]
      )
    }
    try await Wait.until(
      { await setSize.value == 0 },
      { "Expected re-emission with zero embeddings, got \(await setSize.value)" }
    )
  }

  @Test("does not re-emit when an existing embedding's vector is updated")
  func suppressesUnchangedIDSet() async throws {
    let podcast = try await insertPodcast()
    let episode = try await upsertEpisode(podcast: podcast)
    try await upsertEmbedding(for: episode, vector: [1, 0, 0], sourceHash: "v1")

    let emissionCount = Counter()
    Task {
      for try await _ in observatory.episodeEmbeddingIDs() {
        await emissionCount.increment()
      }
    }
    try await emissionCount.wait(for: 1)

    // Re-upsert the same row with a different vector and sourceHash — same
    // episodeId, so the projected ID set is unchanged. GRDB will re-fetch
    // (the table is in the tracked region), and `.removeDuplicates()` must
    // suppress the emission.
    try await upsertEmbedding(for: episode, vector: [0, 1, 0], sourceHash: "v2")

    try await Wait.until(
      maxAttempts: 50,
      { await emissionCount.maxValue == 1 },
      {
        "Expected emission count to remain at 1 after vector update, "
          + "got \(await emissionCount.maxValue)"
      }
    )
  }

  @Test("does not re-emit on Episode or Podcast column mutations")
  func ignoresIrrelevantTables() async throws {
    let podcast = try await insertPodcast()
    let episode = try await upsertEpisode(podcast: podcast)
    try await upsertEmbedding(for: episode)

    let emissionCount = Counter()
    Task {
      for try await _ in observatory.episodeEmbeddingIDs() {
        await emissionCount.increment()
      }
    }
    try await emissionCount.wait(for: 1)

    // Sweep mutations across both tables that the region must not track.
    // Each one would fire if a join accidentally widened the region.
    _ = try await repo.updateCurrentTime(episode.id, currentTime: CMTime.seconds(30))
    _ = try await repo.updateDuration(
      episode.id,
      duration: CMTime(seconds: 1900, preferredTimescale: 1)
    )
    _ = try await repo.updateCachedFilename(episode.id, cachedFilename: "f.mp3")
    _ = try await repo.updateSaveInCache(episode.id, saveInCache: true)
    _ = try await repo.updateRating(episode.id, rating: .liked)

    _ = try await repo.updateDefaultPlaybackRate(podcast.id, defaultPlaybackRate: 1.5)
    _ = try await repo.updateQueueAllEpisodes(podcast.id, queueAllEpisodes: .onTop)
    _ = try await repo.updateCacheAllEpisodes(podcast.id, cacheAllEpisodes: .save)
    _ = try await repo.updateNotifyNewEpisodes(podcast.id, notifyNewEpisodes: true)
    _ = try await repo.updateLastUpdate(podcast.id)

    try await Wait.until(
      maxAttempts: 50,
      { await emissionCount.maxValue == 1 },
      {
        "Expected emission count to remain at 1 across irrelevant mutations, "
          + "got \(await emissionCount.maxValue)"
      }
    )
  }
}
